// Flawless Graphite v1
// Blink Shell theme by Flawless Studio
// github.com/flawlessstudio/flawless-dotfiles
//
// Palette: dark graphite base · cold-clear foreground · semantic ANSI 16
// Optimized for: ssh, mosh, tmux, git diff, logs — long sessions on iPhone
// Settings: Enable Bold ON · Bold as Bright OFF · Cursor Blink OFF

black        = '#1A1F27';
red          = '#E26D77';
green        = '#98C379';
yellow       = '#D8BE84';
blue         = '#6CA9FF';
magenta      = '#C792EA';
cyan         = '#5FBBC2';
white        = '#AEB8C5';

lightBlack   = '#566072';
lightRed     = '#FF8A93';
lightGreen   = '#B6E38D';
lightYellow  = '#EFD49B';
lightBlue    = '#8CC0FF';
lightMagenta = '#D9AEFF';
lightCyan    = '#86DDE3';
lightWhite   = '#F6FAFF';

t.prefs_.set('color-palette-overrides', [
  black,      red,          green,       yellow,
  blue,       magenta,      cyan,        white,
  lightBlack, lightRed,     lightGreen,  lightYellow,
  lightBlue,  lightMagenta, lightCyan,   lightWhite
]);

t.prefs_.set('foreground-color', '#E7EDF5');
t.prefs_.set('background-color', '#0F1216');
t.prefs_.set('cursor-color',     'rgba(231, 237, 245, 0.42)');
t.prefs_.set('cursor-blink',     false);
