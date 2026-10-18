export type PhotoExtractionErrorCode = "provider_unavailable" | "provider_timeout" | "invalid_extraction";

const messages: Record<PhotoExtractionErrorCode, string> = {
  provider_unavailable: "Photo reading is unavailable. Try again or enter the readings yourself.",
  provider_timeout: "Photo reading took too long. Try again or enter the readings yourself.",
  invalid_extraction: "We could not read this photo clearly. Try another photo or enter the readings yourself.",
};

export class PhotoExtractionError extends Error {
  readonly code: PhotoExtractionErrorCode;
  constructor(code: PhotoExtractionErrorCode) {
    super(messages[code]);
    this.name = "PhotoExtractionError";
    this.code = code;
  }
}
