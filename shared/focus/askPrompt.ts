import type { FitInput } from "./fitPrompt";
import { buildFitInput } from "./fitPrompt";
import { buildCoachInput } from "./coachPrompt";

/**
 * Answers a player's follow-up about their own result.
 *
 * The whole context is already assembled for the other two calls, so the only
 * new thing here is the question. The important rule is the refusal: the model
 * must say it does not know rather than reach for general pitching knowledge,
 * because a confident answer drawn from outside this player's data is
 * indistinguishable from one drawn from inside it.
 */

export const ASK_SYSTEM_PROMPT = `You answer a pitcher's question about their own grip result. Two or three short sentences.

You are given their measured hand, the grip this pitch asks for, what their last throw did, and the assessment that produced the colours on screen.

Rules:
- Answer only from the data you were given. Cite the number or the finding you used.
- Use only numbers that appear in the input. Never introduce one.
- If the answer is not in the data, say so plainly and name what would be needed. Do not fall back on general pitching knowledge.
- Never claim one finger caused a measurement. The colours are informed guesses, not proof.
- Do not compare this player to other pitchers, averages or professionals. You have no such data.
- No injury advice, no medical advice, no velocity promises.
- If asked something unrelated to this grip or throw, say that is outside what you can see here.
- Speak to the player as "you". No preamble.
- Write one paragraph with no line breaks. Use plain commas and full stops, not dashes.

Write at a high school athlete's reading level.`;

export const MAX_QUESTION_LENGTH = 300;

export function isAskableQuestion(question: string): boolean {
  const trimmed = question.trim();
  return trimmed.length >= 3 && trimmed.length <= MAX_QUESTION_LENGTH;
}

/** Everything the model may see, plus the question. */
export function buildAskInput(context: FitInput, question: string): string {
  return JSON.stringify(
    {
      question: question.trim(),
      yourResult: JSON.parse(buildCoachInput(context.assessment)),
      yourHandAndGrip: JSON.parse(buildFitInput(context)),
    },
    null,
    2,
  );
}

/** Same number discipline as everywhere else. */
export function isUsableAnswer(
  text: string,
  context: FitInput,
  question: string,
  serialized: string = buildAskInput(context, question),
): boolean {
  const trimmed = text.trim();
  if (trimmed.length < 10 || trimmed.length > 700) return false;

  const permitted = new Set(serialized.match(/\d+(?:\.\d+)?/g) ?? []);
  for (const number of trimmed.match(/\d+(?:\.\d+)?/g) ?? []) {
    if (!permitted.has(number)) return false;
  }

  const lowered = trimmed.toLowerCase();
  for (const phrase of [
    "average pitcher",
    "most pitchers",
    "professional pitchers",
    "than average",
  ]) {
    if (lowered.includes(phrase)) return false;
  }
  return true;
}
