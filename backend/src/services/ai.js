import { callOpenAi, extractJsonObject, extractOpenAiOutputText } from "./openai.js";

export async function analyzeMeal(body) {
  const images = Array.isArray(body.images) ? body.images : [];
  const userEditedSummary = String(body.userEditedSummary || "").trim();
  if (images.length === 0 && !userEditedSummary) {
    throw new Error("At least one image or a meal description is required");
  }

  const input = [
    {
      role: "user",
      content: [
        {
          type: "input_text",
          text:
            `Analyze this ${body.mealType || "meal"} captured at ${body.capturedAt || "unknown time"}. ` +
            "If images are provided, estimate the full meal exactly as shown now across all images, including shared dishes for the whole table when relevant. " +
            "If no images are provided, rely on the user-written meal description only and say so implicitly through your estimate. " +
            "Use the user diet goal context when it is provided, but do not force the answer to sound medical or judgmental. " +
            "If the images only show a drink, fruit, dessert, or a very small item, say that directly instead of inventing a rice or protein plate. " +
            'If the images clearly show only a beverage, set detectedMealType to "drink" and estimateDrinkVolumeMl to a reasonable integer guess for the visible liquid. ' +
            "Do not reuse assumptions from earlier images beyond what is visibly present in the current set. " +
            "If the user has typed extra meal details, use them as additional context, especially counts like number of dishes, cups, glasses, bowls, portions, or water volume. " +
            "When estimating calories, count the whole meal across all visible items and the user-provided dish count or portion note when it fits the images or text description. " +
            "Do not guess how much the user personally ate unless the user explicitly gives a portion clue. " +
            "Return strict JSON only with keys: summary, estimatedCalories, review, detectedMealType, estimatedDrinkVolumeMl. " +
            "The summary should be a concise meal description. estimatedCalories must be an integer. " +
            "review should be one short helpful note about the meal for diet tracking. " +
            "detectedMealType must be one of: breakfast, lunch, dinner, snack, drink, or null. " +
            "estimatedDrinkVolumeMl must be an integer or null."
        },
        ...(body.dietGoalBrief
          ? [
              {
                type: "input_text",
                text: `User diet goal context: ${body.dietGoalBrief}`
              }
            ]
          : []),
        ...(userEditedSummary
          ? [
              {
                type: "input_text",
                text: `User-added meal details to consider if they match the images: ${userEditedSummary}`
              }
            ]
          : []),
        ...images.map((image) => ({
          type: "input_image",
          image_url: `data:${image.mimeType || "image/jpeg"};base64,${image.base64}`
        }))
      ]
    }
  ];

  const data = await callOpenAi(input);
  const outputText = extractOpenAiOutputText(data);
  const parsed = extractJsonObject(outputText);

  return {
    summary: String(parsed.summary || "").trim(),
    estimatedCalories: Number(parsed.estimatedCalories || 0),
    review: String(parsed.review || "").trim(),
    detectedMealType:
      parsed.detectedMealType == null ? null : String(parsed.detectedMealType),
    estimatedDrinkVolumeMl:
      parsed.estimatedDrinkVolumeMl == null
        ? null
        : Number(parsed.estimatedDrinkVolumeMl)
  };
}

export async function createDietGoalBrief(body) {
  const mission = String(body.mission || "").trim();
  if (!mission) {
    return { brief: "" };
  }

  const data = await callOpenAi([
    {
      role: "user",
      content: [
        {
          type: "input_text",
          text:
            "Condense this diet mission into a very short reusable AI context brief. " +
            "Keep the user intent, preferred outcome, and important guardrails. " +
            "Do not repeat filler words. Keep it under 35 words. " +
            `Return strict JSON only with key: brief.\n\nMission: ${mission}`
        }
      ]
    }
  ]);

  const parsed = extractJsonObject(extractOpenAiOutputText(data));
  return {
    brief: String(parsed.brief || "").trim()
  };
}

export async function coachChat(body) {
  const message = String(body.message || "").trim();
  if (!message) {
    return {
      reply:
        "Tell me what you want help with, and I will look at your recent meals with you."
    };
  }

  const dietGoalBrief = String(body.dietGoalBrief || "").trim();
  const recentSummary = String(
    body.recentSummary || "No recent meals were logged."
  ).trim();
  const conversationMessages = Array.isArray(body.conversationMessages)
    ? body.conversationMessages
        .filter((item) => item && typeof item === "object")
        .slice(-8)
    : [];

  const data = await callOpenAi([
    {
      role: "system",
      content: [
        {
          type: "input_text",
          text:
            "You are Mira, the in-app meal reflection coach for Meal Mirror. " +
            "Be warm, observant, concise, and non-judgmental. " +
            "Do not pretend to be a doctor. " +
            "Use the user mission and recent meal history to answer clearly. " +
            "Prefer practical, specific advice over generic nutrition talk. " +
            "Keep replies under 140 words unless the user asks for more detail."
        }
      ]
    },
    {
      role: "user",
      content: [
        ...(dietGoalBrief
          ? [
              {
                type: "input_text",
                text: `Diet mission: ${dietGoalBrief}`
              }
            ]
          : []),
        ...conversationMessages.map((item) => ({
          type: "input_text",
          text: `${item.isUser ? "User" : "Mira"}: ${String(item.text || "").trim()}`
        })),
        {
          type: "input_text",
          text: `Recent meals:\n${recentSummary}`
        },
        {
          type: "input_text",
          text: `User message: ${message}`
        }
      ]
    }
  ]);

  return {
    reply: extractOpenAiOutputText(data).trim()
  };
}
