import type { MobileDialogSnapshot } from './agent-snapshot.ts';

/** Permission actions map one advertised action to one key on the original component. */
export interface PermissionRenderActions {
  kind: 'permission' | 'terminal';
  acceptsText: boolean;
  options: MobileDialogSnapshot['options'];
  keys: Map<string, string>;
}

const fallback = (): PermissionRenderActions => ({ kind: 'terminal', acceptsText: false, options: [], keys: new Map() });

/** Parse only the live public rendering grammar of pi-permission-system 40.1.3. */
export function parsePermissionRender(lines: string[]): PermissionRenderActions {
  const lastBlank = lines.findLastIndex((line) => !line.trim());
  if (lastBlank < 0) return fallback();
  const footer = lines.slice(lastBlank + 1).join(' ').trim();
  const text = lines.join('\n');
  const keys = new Map<string, string>();
  const options: MobileDialogSnapshot['options'] = [];
  const add = (id: string, label: string, key: string, acceptsValue = false) => { options.push({ id, label, ...(acceptsValue ? { acceptsValue: true } : {}) }); keys.set(id, key); };
  if (lines.includes('Reason (required):') && footer === 'enter submit · esc back') {
    add('reason.append', 'Append reason text', 'paste', true);
    add('reason.submit', 'Submit reason (Enter)', '\r');
    add('reason.back', 'Back (Esc)', '\x1b');
    return { kind: 'permission', acceptsText: true, options, keys };
  }
  if (lines[1]?.trim() === 'Apply this session grant to:' && footer === '↑/↓ move · enter confirm · esc back') {
    const rows = lines.slice(3, lastBlank);
    const selected = rows.find((line) => line.startsWith('▶ '));
    if (rows.length !== 2 || !selected || rows.some((row) => /…|\.\.\./.test(row))) return fallback();
    add('scope.up', 'Move up (↑)', '\x1b[A'); add('scope.down', 'Move down (↓)', '\x1b[B');
    add('scope.confirm', `Confirm selected: ${selected.slice(2)}`, '\r'); add('scope.back', 'Back (Esc)', '\x1b');
    return { kind: 'permission', acceptsText: false, options, keys };
  }
  const optionStart = lines.slice(0, lastBlank).findLastIndex((line) => !line.trim()) + 1;
  const optionLines = lines.slice(optionStart, lastBlank);
  const rows = optionLines.map((line) => line.match(/^[▶ ] \((.)\) (.+)$/)).filter((row): row is RegExpMatchArray => row !== null);
  // Any wrapped/missing option label fails closed; never publish a partial grant width.
  if (rows.length !== optionLines.length || rows.length < 3 || rows.length > 5 || rows.some((row) => /…|\.\.\./.test(row[2]) || !/^[a-z0-9`\-=\[\]\\;',./!@#$%^&*()_|~{}:<>?]$/.test(row[1]) || ['j', 'k'].includes(row[1]))) return fallback();
  if (!footer.includes('enter confirm') && !/^Press . again to .+\.$/.test(footer)) return fallback();
  if (!rows.some((row) => row[2] === 'Yes') || !rows.some((row) => row[2] === 'No')) return fallback();
  for (const row of rows) {
    if ([...keys.values()].includes(row[1])) return fallback();
    add(`key.${row[1]}`, `(${row[1]}) ${row[2]}`, row[1]);
  }
  // Hotkeys are deliberately not followed by Enter: double confirmation remains visible.
  return { kind: 'permission', acceptsText: false, options, keys };
}
