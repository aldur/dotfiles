const catalog = await Bun.file("catalog.json").json();
if (!catalog["privatemode-ai"]?.models?.["glm-5.3-flash"]?.limit?.context) {
  throw new Error("Missing Privatemode model metadata");
}
for (const id of ["Qwen/Qwen3-Embedding-0.6B", "qwen/qwen3.7-max"]) {
  if (!catalog.nearai?.models?.[id]) throw new Error(`Missing case-sensitive model ID: ${id}`);
}
