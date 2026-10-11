import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';
import type { ExtensionUIContext, ExtensionUIDialogOptions } from '@earendil-works/pi-coding-agent';
import { BridgeFailure, requireBridgeString } from './bridge-records.mjs';
import { boundedMobileText, type MobileDialogSnapshot } from './agent-snapshot.ts';
import { parsePermissionRender, type PermissionRenderActions } from './permission-render.ts';

type CustomFactory = Parameters<ExtensionUIContext['custom']>[0];
type CustomComponent = Awaited<ReturnType<CustomFactory>>;
interface ActiveMobileDialog {
  snapshot: MobileDialogSnapshot;
  respond(action: string, value: unknown): void;
  refresh?(): void;
  restore?(): void;
}

function permissionVersionSupported(): boolean {
  try {
    // Only public package identity is read; never permission config or private component state.
    const file = join(process.env.PI_MOBILE_PERMISSION_PACKAGE ?? join(homedir(), '.pi/agent/npm/node_modules/@gotgenes/pi-permission-system'), 'package.json');
    const manifest = JSON.parse(readFileSync(file, 'utf8')) as { name?: string; version?: string };
    return manifest.name === '@gotgenes/pi-permission-system' && manifest.version === '40.1.3';
  } catch { return false; }
}

/** Wrap the shared Pi UI promises; the original desktop interaction always wins races. */
export class AgentDialogBridge {
  private active: ActiveMobileDialog | null = null;
  private stopped = false;
  private restoreCallbacks: (() => void)[] = [];
  private readonly permissionSupported = permissionVersionSupported();
  private unsubscribeInput: () => void;
  constructor(private readonly ui: ExtensionUIContext, private readonly changed: () => void) {
    this.unsubscribeInput = ui.onTerminalInput(() => {
      if (this.active) {
        this.active.snapshot.revision++;
        if (['select', 'confirm', 'input'].includes(this.active.snapshot.kind)) {
          // Generic Pi promises expose no live selection/draft or focus handle. After local
          // interaction, do not let a fresh phone reply overwrite unseen desktop state.
          this.active.snapshot.kind = 'terminal'; this.active.snapshot.options = []; this.active.snapshot.acceptsText = false;
          this.active.snapshot.text = 'Desktop interaction is authoritative; finish this dialog in the terminal.';
        }
        this.changed();
      }
      return undefined;
    });
    this.installGenericDialogs();
    this.installCustomDialogs();
    // Pi 1.1.0 editor has no owned AbortSignal cancellation. Do not fake its completion.
    const originalEditor = ui.editor;
    const editorWrapper: ExtensionUIContext['editor'] = async (title, prefill) => {
      const active = this.openTerminalDialog(title, 'Use the terminal editor; Pi 1.1.0 exposes no safe cancellation handle.');
      try { return await originalEditor.call(ui, title, prefill); } finally { this.closeDialog(active); }
    };
    ui.editor = editorWrapper;
    this.restoreCallbacks.push(() => { if (ui.editor === editorWrapper) ui.editor = originalEditor; });
  }
  /** Return the latest rendered dialog; re-render before every revision-checked reply. */
  snapshot(): MobileDialogSnapshot | null { this.active?.refresh?.(); return this.active ? structuredClone(this.active.snapshot) : null; }
  /** Reject replaced dialogs and stale desktop revisions before touching any original UI. */
  respond(params: Record<string, unknown>): void {
    this.active?.refresh?.();
    const active = this.active;
    if (this.stopped || !active || params.dialogId !== active.snapshot.dialogId || params.revision !== active.snapshot.revision) throw new BridgeFailure('stale_dialog', 'dialog closed, changed or was replaced; reload its snapshot.');
    const action = requireBridgeString(params.action, 128);
    if (!active.snapshot.options.some((option) => option.id === action)) throw new BridgeFailure('unknown_option', 'only currently advertised dialog actions are allowed.');
    if (params.value !== undefined && !active.snapshot.options.some((option) => option.id === action && option.acceptsValue === true)) throw new BridgeFailure('invalid_request', 'this advertised action does not accept free text.');
    if (params.value !== undefined && (typeof params.value !== 'string' || params.value.length > 8192 || /[\x00-\x1f\x7f-\x9f]/u.test(params.value))) throw new BridgeFailure('invalid_request', 'dialog free text contains control characters or exceeds its limit.');
    active.respond(action, params.value);
    this.changed();
  }
  /** Restore only wrappers owned by this runtime; shutdown never approves or cancels a dialog. */
  stop(): void {
    if (this.stopped) return;
    this.stopped = true; this.unsubscribeInput(); this.active?.restore?.(); this.active = null;
    for (const restore of this.restoreCallbacks.reverse()) restore();
  }
  private activate(active: ActiveMobileDialog): ActiveMobileDialog {
    this.active?.restore?.(); this.active = active; this.changed(); return active;
  }
  private closeDialog(active: ActiveMobileDialog): void {
    active.restore?.(); if (this.active === active) { this.active = null; this.changed(); }
  }
  private openTerminalDialog(title: string, text: string): ActiveMobileDialog {
    return this.activate({ snapshot: { dialogId: randomUUID(), revision: 1, kind: 'terminal', title: boundedMobileText(title, 1024), text: boundedMobileText(text, 16384), options: [], acceptsText: false }, respond() { throw new BridgeFailure('terminal_fallback', 'this UI is available only in the terminal.'); } });
  }
  private installGenericDialogs(): void {
    const { ui } = this;
    const originalSelect = ui.select, originalConfirm = ui.confirm, originalInput = ui.input;
    const selectWrapper: ExtensionUIContext['select'] = (title, options, opts) => this.genericDialog('select', title, '', options.map((label, index) => ({ id: `select.${index}`, label })), false, opts, (merged) => originalSelect.call(ui, title, options, merged), (action) => action === 'cancel' ? undefined : options[Number(action.slice(7))]);
    const confirmWrapper: ExtensionUIContext['confirm'] = (title, text, opts) => this.genericDialog('confirm', title, text, [{ id: 'yes', label: 'Yes' }, { id: 'no', label: 'No' }], false, opts, (merged) => originalConfirm.call(ui, title, text, merged), (action) => action === 'yes');
    const inputWrapper: ExtensionUIContext['input'] = (title, placeholder, opts) => this.genericDialog('input', title, placeholder ?? '', [{ id: 'submit', label: 'Submit', acceptsValue: true }], true, opts, (merged) => originalInput.call(ui, title, placeholder, merged), (action, value) => action === 'cancel' ? undefined : String(value ?? ''));
    ui.select = selectWrapper; ui.confirm = confirmWrapper; ui.input = inputWrapper;
    this.restoreCallbacks.push(() => { if (ui.select === selectWrapper) ui.select = originalSelect; if (ui.confirm === confirmWrapper) ui.confirm = originalConfirm; if (ui.input === inputWrapper) ui.input = originalInput; });
  }
  private async genericDialog<T>(kind: 'select' | 'confirm' | 'input', title: string, text: string, options: MobileDialogSnapshot['options'], acceptsText: boolean, opts: ExtensionUIDialogOptions | undefined, original: (options: ExtensionUIDialogOptions) => Promise<T>, convert: (action: string, value: unknown) => T): Promise<T> {
    if (this.stopped || opts?.signal?.aborted) return original(opts ?? {});
    const controller = new AbortController();
    const signal = opts?.signal ? AbortSignal.any([opts.signal, controller.signal]) : controller.signal;
    let mobileAnswer: { result: T } | undefined;
    let desktopClosed = false;
    const native = options.length <= 128 && !opts?.timeout && Buffer.byteLength(title) <= 1024 && Buffer.byteLength(text) <= 16384 && options.every((option) => Buffer.byteLength(option.label) <= 1024);
    const active = this.activate({ snapshot: { dialogId: randomUUID(), revision: 1, kind: native ? kind : 'terminal', title: boundedMobileText(title, 1024), text: boundedMobileText(text, 16384), options: native ? [...options.map((option) => ({ ...option, label: boundedMobileText(option.label, 1024) })), { id: 'cancel', label: 'Cancel' }] : [], acceptsText: native && acceptsText },
      respond: (action, value) => {
        if (desktopClosed || signal.aborted || this.active !== active) throw new BridgeFailure('stale_dialog', 'the original desktop dialog is already closed.');
        if (!acceptsText && value !== undefined) throw new BridgeFailure('invalid_request', 'this dialog does not accept free text.');
        if (action === 'submit' && typeof value !== 'string') throw new BridgeFailure('invalid_request', 'a text answer is required.');
        mobileAnswer = { result: convert(action, value) };
        // Owned abort dismisses only this original prompt, then its wrapper completes to its caller.
        controller.abort(); desktopClosed = true; this.closeDialog(active);
      },
    });
    try { const result = await original({ ...opts, signal }); desktopClosed = true; return mobileAnswer ? mobileAnswer.result : result; }
    finally { desktopClosed = true; this.closeDialog(active); }
  }
  private installCustomDialogs(): void {
    const { ui } = this;
    const originalCustom = ui.custom;
    const customWrapper: ExtensionUIContext['custom'] = async <T>(factory: (tui: Parameters<CustomFactory>[0], theme: Parameters<CustomFactory>[1], keybindings: Parameters<CustomFactory>[2], done: (result: T) => void) => CustomComponent | Promise<CustomComponent>, options?: Parameters<ExtensionUIContext['custom']>[1]): Promise<T> => {
      const active = this.openTerminalDialog('Custom Pi UI', 'This interface requires the terminal.');
      try {
        return await originalCustom.call(ui, async (tui, theme, keybindings, done) => {
          const component = await factory(tui, theme, keybindings, (result) => { this.closeDialog(active); done(result); });
          if (this.stopped || this.active !== active) return component;
          if (this.permissionSupported && component.constructor.name === 'PermissionPromptComponent' && typeof component.render === 'function' && typeof component.handleInput === 'function' && options?.overlay !== true) this.capturePermissionComponent(active, component);
          return component;
        }, options) as T;
      } finally { this.closeDialog(active); }
    };
    ui.custom = customWrapper;
    this.restoreCallbacks.push(() => { if (ui.custom === customWrapper) ui.custom = originalCustom; });
  }
  private capturePermissionComponent(active: ActiveMobileDialog, component: CustomComponent): void {
    const originalRender = component.render;
    const originalInput = component.handleInput!;
    let width = 0;
    let rendered = '';
    let actions: PermissionRenderActions = { kind: 'terminal', acceptsText: false, options: [], keys: new Map() };
    const observe = (lines: string[]) => {
      // Remove display escape codes only; retain complete option labels and step hints.
      const plain = lines.map((line) => boundedMobileText(line, 4096));
      const next = plain.join('\n');
      if (next !== rendered) {
        rendered = next; actions = Buffer.byteLength(next) <= 32768 ? parsePermissionRender(plain) : { kind: 'terminal', acceptsText: false, options: [], keys: new Map() };
        active.snapshot.revision++; active.snapshot.kind = actions.kind;
        active.snapshot.title = plain[0] ?? 'Permission'; active.snapshot.text = boundedMobileText(next, 32768);
        active.snapshot.options = actions.options; active.snapshot.acceptsText = actions.acceptsText;
        this.changed();
      }
    };
    const renderWrapper = (newWidth: number) => { width = newWidth; const lines = originalRender.call(component, newWidth); if (this.active === active && !this.stopped) observe(lines); return lines; };
    const inputWrapper = (data: string) => { if (this.active === active && !this.stopped) active.snapshot.revision++; originalInput.call(component, data); active.refresh?.(); };
    component.render = renderWrapper; component.handleInput = inputWrapper;
    active.refresh = () => { if (width > 0 && this.active === active && !this.stopped) observe(originalRender.call(component, width)); };
    active.restore = () => { if (component.render === renderWrapper) component.render = originalRender; if (component.handleInput === inputWrapper) component.handleInput = originalInput; active.refresh = undefined; };
    active.respond = (action, value) => {
      const key = actions.keys.get(action);
      if (!key) throw new BridgeFailure('unknown_option', 'permission action is not in the current rendering.');
      if (key === 'paste') {
        if (typeof value !== 'string' || !value) throw new BridgeFailure('invalid_request', 'nonempty reason text is required.');
        inputWrapper(`\x1b[200~${value}\x1b[201~`);
      } else {
        if (value !== undefined) throw new BridgeFailure('invalid_request', 'this permission action does not accept free text.');
        inputWrapper(key);
      }
    };
  }
}
