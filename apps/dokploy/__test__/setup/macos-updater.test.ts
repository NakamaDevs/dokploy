import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("@dokploy/server", async (importOriginal) => ({
	...(await importOriginal<typeof import("@dokploy/server")>()),
	IS_CLOUD: false,
	getUpdateData: vi.fn(async () => ({
		updateAvailable: true,
		latestVersion: "v99.0.0",
	})),
	spawnAsync: vi.fn(async () => undefined),
}));
vi.mock("@/server/api/utils/audit", () => ({ audit: vi.fn() }));

import { getUpdateData, spawnAsync } from "@dokploy/server";
import { settingsRouter } from "@/server/api/routers/settings";

afterEach(() => {
	vi.unstubAllEnvs();
	vi.clearAllMocks();
});

const caller = () =>
	settingsRouter.createCaller({
		session: {},
		user: { role: "owner" },
	} as Parameters<typeof settingsRouter.createCaller>[0]);

describe("macOS dashboard updater", () => {
	it("rejects upstream replacement before checking or spawning an update", async () => {
		vi.stubEnv("DOKPLOY_HOST_ROOT_PATH", "/Users/operator/dokploy");
		await expect(caller().updateServer()).rejects.toMatchObject({
			code: "PRECONDITION_FAILED",
		});
		expect(getUpdateData).not.toHaveBeenCalled();
		expect(spawnAsync).not.toHaveBeenCalled();
	});

	it("preserves the upstream updater for installations without a host override", async () => {
		vi.stubEnv("DOKPLOY_HOST_ROOT_PATH", "");
		await expect(caller().updateServer()).resolves.toBe(true);
		expect(spawnAsync).toHaveBeenCalledWith("docker", [
			"service",
			"update",
			"--force",
			"--image",
			"dokploy/dokploy:v99.0.0",
			"dokploy",
		]);
	});
});
