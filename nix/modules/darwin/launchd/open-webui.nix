{
  pkgs,
  user,
  lib,
  config,
  ...
}:
with lib;
let
  name = "open-webui";
  cfg = config.programs.${name};
in
{
  options.programs.${name} = {
    enable = mkEnableOption "open-webui server";
  };

  config = mkIf cfg.enable {
    launchd = {
      user = {
        agents = {
          open-webui = {
            command = "sandbox-exec -f ${../../../../osx/sandboxes/open-webui.sb} ${pkgs.lib.getExe pkgs.open-webui} serve --host 127.0.0.1 --port 8080";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
              StandardErrorPath = "/tmp/open-webui/std.err";
              StandardOutPath = "/tmp/open-webui/std.log";
              WorkingDirectory = "/Users/${user}/.cache/open-webui/";
            };
            environment = {
              ENV = "prod";
              WEBUI_AUTH = "False";
              DATA_DIR = "/Users/${user}/.cache/open-webui/data";
              ENABLE_SIGNUP = "False";
              ENABLE_COMMUNITY_SHARING = "False";
              ENABLE_MESSAGE_RATING = "False";
              ENABLE_EVALUATION_ARENA_MODELS = "False";
              ENABLE_OPENAI_API = "False";
              ENABLE_RAG_LOCAL_WEB_FETCH = "False";
              ENABLE_GOOGLE_DRIVE_INTEGRATION = "False";
              ENABLE_RAG_WEB_SEARCH = "False";
              RAG_EMBEDDING_MODEL_AUTO_UPDATE = "False";
              RAG_RERANKING_MODEL_AUTO_UPDATE = "False";
              WHISPER_MODEL_AUTO_UPDATE = "False";
              SAFE_MODE = "True";
            };
          };
        };
      };
    };
  };
}
