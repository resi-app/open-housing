import { NextRequest, NextResponse } from "next/server";
import { validateApiKeyFromRequest, type ValidatedApiKey } from "./api-keys";
import type { ApiKeyPermission } from "@/types";

const PERMISSION_HIERARCHY: Record<ApiKeyPermission, number> = {
  read: 1,
  read_write: 2,
  full: 3,
};

function hasRequiredPermission(
  actual: ApiKeyPermission,
  required: ApiKeyPermission
): boolean {
  return PERMISSION_HIERARCHY[actual] >= PERMISSION_HIERARCHY[required];
}

type ExternalHandler = (
  request: NextRequest,
  apiKey: ValidatedApiKey,
  context?: { params: Promise<Record<string, string>> }
) => Promise<NextResponse>;

export function withExternalAuth(
  handler: ExternalHandler,
  requiredPermission: ApiKeyPermission
) {
  return async (
    request: NextRequest,
    context?: { params: Promise<Record<string, string>> }
  ) => {
    const apiKey = await validateApiKeyFromRequest(request);

    if (!apiKey) {
      return NextResponse.json(
        { error: "Missing or invalid API key" },
        { status: 401 }
      );
    }

    if (!hasRequiredPermission(apiKey.permissions, requiredPermission)) {
      return NextResponse.json(
        { error: "Insufficient permissions" },
        { status: 403 }
      );
    }

    return handler(request, apiKey, context);
  };
}
