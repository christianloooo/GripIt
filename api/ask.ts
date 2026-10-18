import { jsonEndpoint } from "./_http";
import { isAskRequest } from "./_validation";
import type { FitInput } from "../shared/focus/fitPrompt";
import { isAskableQuestion } from "../shared/focus/askPrompt";
import {
  INTERPRET_SYSTEM_PROMPT,
  buildInterpretationInput,
  isUsableInterpretation,
} from "../shared/focus/interpretation";
import { generate } from "./_client";

export interface AskResponse {
  answer: string;
  answered: boolean;
  reason?: string;
}

/** What the player sees when the model cannot or should not answer. */
const DECLINE =
  "I can only answer from this scan and this throw, and I cannot see enough here to say. Try entering another throw.";

export async function answerQuestion(
  context: FitInput,
  question: string,
  apiKey: string | undefined,
): Promise<AskResponse> {
  if (!isAskableQuestion(question)) {
    return { answer: DECLINE, answered: false, reason: "bad-question" };
  }
  const input = buildInterpretationInput(context, question);
  const outcome = await generate({
    apiKey,
    system: INTERPRET_SYSTEM_PROMPT,
    input,
    maxTokens: 700,
    reject: (text) => (isUsableInterpretation(text, input) ? null : "rejected"),
  });
  return outcome.ok
    ? { answer: outcome.text, answered: true }
    : { answer: DECLINE, answered: false, reason: outcome.reason };
}

export function handleAskRequest(
  request: Request,
  apiKey: string | undefined,
): Promise<Response> {
  return jsonEndpoint(
    request,
    isAskRequest,
    (body: FitInput & { question: string }) =>
      answerQuestion(body, body.question, apiKey),
  );
}

export default function handler(request: Request): Promise<Response> {
  return handleAskRequest(request, process.env.ANTHROPIC_API_KEY);
}
