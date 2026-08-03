export function reconcilePersistedValue<T>(current: T, submittedText: string, persisted: T): T {
  return JSON.stringify(current) === submittedText ? persisted : current;
}
