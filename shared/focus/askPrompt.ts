/**
 * The one check the ask endpoint makes before spending anything.
 *
 * The question box is still AI, and its prompt, input and output guard all
 * live in `interpretation.ts` alongside the ask path's single model call. What
 * is left here is the cheap pre-flight: a question too short to mean anything
 * or long enough to be a payload never reaches the provider at all.
 *
 * The prompt this file used to hold went out with the coaching rewrite. It had
 * no production caller: `api/ask.ts` has always used INTERPRET_SYSTEM_PROMPT.
 */

export const MAX_QUESTION_LENGTH = 300;

export function isAskableQuestion(question: string): boolean {
  const trimmed = question.trim();
  return trimmed.length >= 3 && trimmed.length <= MAX_QUESTION_LENGTH;
}
