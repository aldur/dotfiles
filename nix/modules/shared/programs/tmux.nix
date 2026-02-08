# Shared tmux settings.
# Consumed by home-manager (programs.tmux) and NixOS (programs.tmux).
# NixOS uses `shortcut` instead of `prefix`, and lacks `mouse`/`focusEvents`
# options — callers must set those themselves.
{ pkgs }:
{
  terminal = "tmux-256color";
  baseIndex = 1;
  clock24 = true;
  customPaneNavigationAndResize = true;
  # https://neovim.io/doc/user/faq.html#_esc-in-tmux-or-gnu-screen-is-delayed
  escapeTime = 10;
  historyLimit = 10000;
  secureSocket = true;
  keyMode = "vi";
  newSession = true;

  extraConfig = ''
    # enable RGB support and make nvim autoread work
    set -as terminal-features ',*-256color:RGB'

    # enable hyperlinks
    set -as terminal-features ",*:hyperlinks"

    # enable undercurl and strikethrough
    set -as terminal-features ',*:usstyle'
    set -as terminal-features ',*:strikethrough'

    # mouse support
    set -g mouse on

    # required by nvim
    set-option -g focus-events on

    # automatically re-number windows (do not leave gaps)
    set -g renumber-windows on

    # c-a twice sends c-a to the terminal
    bind C-a send-prefix

    # Center the window list
    set -g status-justify centre

    # split with vi keybindings opening to the current pane's path
    bind-key s split-window -v -c "#{pane_current_path}"
    bind-key v split-window -h -c "#{pane_current_path}"

    # v, c-v to select and vertically select
    bind -T copy-mode-vi v send-keys -X begin-selection
    bind -T copy-mode-vi C-v send-keys -X rectangle-toggle
    # escape to exit copy mode
    bind -T copy-mode-vi Escape send-keys -X cancel

    # Jump to previous/next prompt with [ and ]
    bind-key -T copy-mode-vi [ send-keys -X previous-prompt
    bind-key -T copy-mode-vi ] send-keys -X next-prompt

    # --- Theming ---
    set -g @tokyo-night-tmux_transparent 1

    # Stripped down version of https://github.com/janoamaral/tokyo-night-tmux
    # Night theme colors
    # BG supports transparent mode via @tokyo-night-tmux_transparent
    %hidden BG="#{?#{==:#{@tokyo-night-tmux_transparent},1},default,#1A1B26}"
    %hidden FG="#a9b1d6"
    %hidden BBLACK="#2A2F41"
    %hidden BLUE="#7aa2f7"
    %hidden GREEN="#73daca"
    %hidden BGREEN="#41a6b5"
    %hidden YELLOW="#e0af68"

    # Status bar
    set -g status-left-length 40
    set -g status-right-length 80
    set -g status-style "bg=#{BG}"

    # Highlight & messages
    set -g mode-style "fg=#{BGREEN},bg=#{BBLACK}"
    set -g message-style "bg=#{BLUE},fg=#{BBLACK}"
    set -g message-command-style "fg=#{BLUE},bg=#{BBLACK}"

    # Panes: borders
    set -g pane-border-lines heavy
    set -g pane-border-style "fg=#{BBLACK}"
    set -g pane-active-border-style "fg=#{BLUE}"

    # Panes: status (set it to `top` when you need it)
    set -g pane-border-status off
    set -g pane-border-format "#{?pane_active,#[fg=#{BLUE}]  #P: #{pane_title} ,#[fg=#{BBLACK}] #P: #{pane_title} }"

    # Popup
    set -g popup-border-style "fg=#{BLUE}"

    # Status left (session)
    set -g status-left "#[fg=#{BBLACK},bg=#{BLUE},bold] #{?client_prefix,󰠠 ,#[dim]󰤂 }#[bold,nodim]#S "

    # Windows
    set -g window-status-current-format "#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#[fg=#{GREEN},bg=#{BBLACK}] #{?#{==:#{pane_current_command},ssh},󰣀 , }#[fg=#{FG},bold,nodim]#I-#P #W#{?window_zoomed_flag, ,}#[nobold]#{?window_last_flag, , }"
    set -g window-status-format "#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#[fg=#{FG}] #{?#{==:#{pane_current_command},ssh},󰣀 , }#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#I-#P #W#{?window_zoomed_flag, ,}#[nobold,dim]#[fg=#{YELLOW}]#{?window_last_flag, 󰁯  , }"
    set -g window-status-separator ""

    # Status right (date/time)
    set -g status-right "#[fg=#{FG},bg=#{BG},nobold,noitalics,nounderscore,nodim]#[fg=#{FG},bg=#{BBLACK}] %Y-%m-%d ❬ %H:%M "
    # --- /Theming ---
  '';

  plugins = with pkgs; [
    tmuxPlugins.yank
  ];
}
