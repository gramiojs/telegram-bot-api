import { Bot } from "gramio";

const API_BASE_URL = process.env.API_BASE_URL ?? "http://localhost:8081/bot";

// Where nginx exposes the working dir (token-less, path-based URLs).
// Set by docker-compose.nginx.yml; absent without the overlay.
const FILES_BASE_URL = process.env.FILES_BASE_URL;
const LOCAL_BOT_API_DIR =
	process.env.LOCAL_BOT_API_DIR ?? "/var/lib/telegram-bot-api";

const bot = new Bot(process.env.BOT_TOKEN as string, {
	api: { baseURL: API_BASE_URL },
});

/**
 * Turn a --local absolute file_path into a token-less download URL served by nginx.
 *
 * Until gramio core ships `files.filesBaseURL` + `bot.getFileLink()`, we do the
 * prefix swap by hand:
 *   /var/lib/telegram-bot-api/<bot_id>/documents/file_5.jpg
 *     -> ${FILES_BASE_URL}/<bot_id>/documents/file_5.jpg
 */
function toDownloadUrl(filePath: string): string | undefined {
	if (!FILES_BASE_URL) return undefined;
	const rel = filePath
		.replace(`${LOCAL_BOT_API_DIR}/`, "")
		.replace(/^\/+/, "");
	return `${FILES_BASE_URL.replace(/\/+$/, "")}/${rel}`;
}

bot.on("message", async (ctx) => {
	const fileId = ctx.document?.fileId ?? ctx.photo?.at(-1)?.fileId;
	if (!fileId) return ctx.send("Send me a file and I'll give you a download link.");

	const file = await bot.api.getFile({ file_id: fileId });
	if (!file.file_path) return ctx.send("File not available.");

	const url = toDownloadUrl(file.file_path);
	return ctx.send(
		url
			? `Download (no token in this link):\n${url}`
			: `Stored on the server at:\n${file.file_path}\n(add the nginx overlay to serve it over HTTP)`,
	);
});

bot.onStart(({ info }) => console.log(`@${info.username} started`));

bot.start();

export { bot };
