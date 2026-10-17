// Shared CLI and editor defaults; project-local configurations take precedence.
const config = {
  MD010: { code_blocks: false }, // Preserve tabs in code blocks and spans.
  MD014: false, // Preserve shell prompts in examples.
  MD026: false, // Preserve heading punctuation.
  MD029: false, // Preserve authored list numbering.
  MD033: false, // Allow inline HTML.
  MD034: false, // Allow bare URLs.
  MD038: false, // Preserve meaningful spaces inside inline code.
  MD044: false, // Preserve capitalization.
  MD053: false, // Preserve unused and duplicate reference definitions.
  MD054: false, // Preserve link labels, titles, and reference structure.
};

// These repairs guess intent. Keep their diagnostics, but exclude them from
// formatting passes (Conform uses --fix; --format is the CLI's stdin equivalent).
if (process.argv.some((arg) => arg === "--fix" || arg === "--format")) {
  for (const rule of ["MD004", "MD011", "MD018", "MD020", "MD037", "MD051"]) {
    config[rule] = false;
  }
}

module.exports = { config };
