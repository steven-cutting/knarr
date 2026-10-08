// Render with the Markdown parser shipped in the pinned markdownlint-cli2
// environment. No npm install, network access, or execution of document content.
import { readFileSync, realpathSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire(realpathSync(process.argv[2]));
const MarkdownIt = require("markdown-it");
const parser = new MarkdownIt({ html: true });
const pages = JSON.parse(readFileSync(0, "utf8"));
const rendered = Object.fromEntries(
  Object.entries(pages).map(([path, text]) => [path, parser.render(text)])
);
process.stdout.write(JSON.stringify(rendered));
