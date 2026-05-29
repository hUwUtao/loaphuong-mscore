const CEPHOME_URL = process.env.CEPHOME_URL ?? "http://127.0.0.1:3000";
const CACHE_DIR = process.env.LOAPHUONG_CACHE ?? `${Bun.env.HOME ?? "/tmp"}/.cache/loaphuong`;

Bun.serve({
	port: 3100,
	async fetch(req) {
		const url = new URL(req.url);

		if (url.pathname === "/api/render" && req.method === "POST") {
			return handleRender(req);
		}

		if (url.pathname === "/api/status" && req.method === "GET") {
			return Response.json({ ok: true });
		}

		return new Response("Not Found", { status: 404 });
	},
});

interface RenderRequest {
	musicxml: string;
	voice?: string;
	model?: string;
}

async function handleRender(req: Request): Promise<Response> {
	const body = (await req.json()) as RenderRequest;

	if (!body.musicxml) {
		return Response.json({ error: "Missing musicxml" }, { status: 400 });
	}

	// Step 1: Call cephome pipeline (MusicXML → phones)
	const cephomeRes = await fetch(`${CEPHOME_URL}/api/render`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify({
			musicxml: body.musicxml,
			voice: body.voice ?? "soprano",
			model: body.model ?? "gpu",
		}),
	});

	if (!cephomeRes.ok) {
		const err = await cephomeRes.text();
		return Response.json({ error: `cephome: ${err}` }, { status: 502 });
	}

	const cephomeResult = await cephomeRes.json();

	// Step 2: Call NEUTRINO model (placeholder — user implements this)
	const wavPath = `${CACHE_DIR}/render.wav`;
	const renderOutput = cephomeResult.output;

	// TODO: replace with actual model call
	// The model reads renderOutput.phones[], generates WAV, writes to wavPath
	renderOutput.audio = {
		format: "wav",
		sampleRate: 48000,
		path: wavPath,
	};

	// Step 3: Signal VST3 by writing to cache path
	await Bun.write(
		`${CACHE_DIR}/render.json`,
		JSON.stringify(renderOutput, null, 2),
	);

	return Response.json({
		success: true,
		wavPath,
		notes: renderOutput.notes.length,
		phones: renderOutput.phones.length,
		output: renderOutput,
	});
}

console.log(`loaphuong backend running at http://127.0.0.1:3100`);
