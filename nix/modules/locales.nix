{ ... }:
let
  defaultLocale = "en_US.UTF-8";
in
{
  # These are the locales that we want to enable.
  i18n.defaultLocale = defaultLocale;
}
