import * as fs from "node:fs";
import subagent from "@subagent@";

export default async function(pi) {
  let tool;
  await subagent({
    ...pi,
    registerTool(definition) {
      tool = definition;
      pi.registerTool(definition);
    },
  });
  pi.on("session_start", () => {
    const child = process.argv.includes("-p");
    fs.appendFileSync(process.env.PI_TEST_LOG, JSON.stringify({
      build: "@build@", child, user: globalThis.piTestUserLoaded === true,
    }) + "\n");
    // Stop before print mode sends the task to a model.
    if (child) process.exit(0);
  });
  pi.registerCommand("check-child", {
    description: "Check the child plugin selection",
    async handler(args, ctx) {
      const result = await tool.execute("check", { agent: "probe", task: "Check plugins" },
        undefined, undefined, { ...ctx, model: undefined });
      fs.writeFileSync(args, JSON.stringify(result));
    },
  });
}
