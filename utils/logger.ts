// Development logging utility.
// Use devLog instead of console.log throughout the app.

export function devLog(...args: unknown[]): void {
  if (__DEV__) {
    // eslint-disable-next-line no-console
    console.log(...args);
  }
}

