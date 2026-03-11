export type DateInput = Date | string;

const pad2 = (n: number) => n.toString().padStart(2, '0');

const monthShortNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function toDate(input: DateInput): Date {
  return input instanceof Date ? input : new Date(input);
}

/** Default format: yyyy/MM/dd */
export function formatDateDefault(input: DateInput): string {
  const d = toDate(input);
  const y = d.getFullYear();
  const m = pad2(d.getMonth() + 1);
  const day = pad2(d.getDate());
  return `${y}/${m}/${day}`;
}

/** Short format: Mon dd (e.g. Mar 03) */
export function formatDateShort(input: DateInput): string {
  const d = toDate(input);
  const month = monthShortNames[d.getMonth()] ?? '';
  const day = pad2(d.getDate());
  return `${month} ${day}`;
}

