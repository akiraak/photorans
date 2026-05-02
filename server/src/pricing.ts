export interface ModelPricing {
  inputPerMTok: number;
  outputPerMTok: number;
  cacheWritePerMTok: number;
  cacheReadPerMTok: number;
}

const PRICING: Record<string, ModelPricing> = {
  'claude-sonnet-4-6': {
    inputPerMTok: 3.0,
    outputPerMTok: 15.0,
    cacheWritePerMTok: 3.75,
    cacheReadPerMTok: 0.3,
  },
};

export interface UsageInput {
  inputTokens: number | null;
  outputTokens: number | null;
  cacheCreationInputTokens: number | null;
  cacheReadInputTokens: number | null;
}

export function getModelPricing(model: string): ModelPricing | null {
  return PRICING[model] ?? null;
}

export function calculateCost(model: string, usage: UsageInput): number | null {
  const pricing = PRICING[model];
  if (!pricing) return null;
  if (usage.inputTokens === null && usage.outputTokens === null) return null;

  const input = usage.inputTokens ?? 0;
  const output = usage.outputTokens ?? 0;
  const cacheWrite = usage.cacheCreationInputTokens ?? 0;
  const cacheRead = usage.cacheReadInputTokens ?? 0;

  return (
    (input * pricing.inputPerMTok +
      output * pricing.outputPerMTok +
      cacheWrite * pricing.cacheWritePerMTok +
      cacheRead * pricing.cacheReadPerMTok) /
    1_000_000
  );
}
