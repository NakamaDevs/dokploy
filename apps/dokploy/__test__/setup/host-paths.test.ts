import { afterEach, describe, expect, it, vi } from "vitest";

afterEach(() => {
	vi.unstubAllEnvs();
	vi.resetModules();
});

describe("Docker host paths", () => {
	it("uses the same local path for files and Docker bind sources", async () => {
		vi.stubEnv("NODE_ENV", "production");
		vi.stubEnv("DOKPLOY_HOST_ROOT_PATH", "/Users/operator/dokploy");
		const { hostPaths, paths } = await import("@dokploy/server/constants");

		expect(paths().BASE_PATH).toBe("/Users/operator/dokploy");
		expect(paths()).toEqual(hostPaths());
		expect(hostPaths().BASE_PATH).toBe("/Users/operator/dokploy");
		expect(hostPaths().MAIN_TRAEFIK_PATH).toBe(
			"/Users/operator/dokploy/traefik",
		);
		expect(hostPaths().MONITORING_PATH).toBe(
			"/Users/operator/dokploy/monitoring",
		);
		expect(hostPaths().CERTIFICATES_PATH).toBe(
			"/Users/operator/dokploy/traefik/dynamic/certificates",
		);
	});

	it("preserves remote Linux paths when the local host has an override", async () => {
		vi.stubEnv("DOKPLOY_HOST_ROOT_PATH", "/Users/operator/dokploy");
		const { hostPaths, paths } = await import("@dokploy/server/constants");

		expect(hostPaths(true)).toEqual(paths(true));
		expect(hostPaths(true).MONITORING_PATH).toBe("/etc/dokploy/monitoring");
	});

	it.each(["production", "development"])(
		"preserves existing %s paths without an override",
		async (mode) => {
			vi.stubEnv("NODE_ENV", mode);
			vi.stubEnv("DOKPLOY_HOST_ROOT_PATH", "");
			const { hostPaths, paths } = await import("@dokploy/server/constants");

			expect(hostPaths()).toEqual(paths());
		},
	);
});
