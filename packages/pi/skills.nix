{ lib, tavily-cli }:
import ../../skills
// lib.optionalAttrs (tavily-cli != null) {
  tavily-search = "${tavily-cli.skills}/tavily-search";
}
