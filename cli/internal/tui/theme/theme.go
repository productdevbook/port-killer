package theme

import "github.com/charmbracelet/lipgloss"

// High-contrast color palette using basic ANSI colors (0-15)
// These are the brightest and most readable in any terminal

// Text colors
var (
	White    = lipgloss.Color("15") // Bright white
	Gray     = lipgloss.Color("7")  // Normal white/gray
	DarkGray = lipgloss.Color("8")  // Bright black (dark gray)
	DimGray  = lipgloss.Color("8")  // Same as dark gray
)

// Accent colors - BASIC ANSI bright colors (most visible)
var (
	Red    = lipgloss.Color("9")  // Bright red
	Green  = lipgloss.Color("10") // Bright green
	Yellow = lipgloss.Color("11") // Bright yellow
	Blue   = lipgloss.Color("12") // Bright blue
	Pink   = lipgloss.Color("13") // Bright magenta/pink
	Cyan   = lipgloss.Color("14") // Bright cyan
	Orange = lipgloss.Color("11") // Use yellow as orange alternative
)

// Theme holds the current color scheme
type Theme struct {
	// Text colors
	Primary   lipgloss.Color
	Secondary lipgloss.Color
	Muted     lipgloss.Color
	Disabled  lipgloss.Color

	// Semantic colors
	Accent  lipgloss.Color
	Success lipgloss.Color
	Warning lipgloss.Color
	Danger  lipgloss.Color
	Info    lipgloss.Color

	// Process type colors
	WebServer   lipgloss.Color
	Database    lipgloss.Color
	Development lipgloss.Color
	System      lipgloss.Color
	Other       lipgloss.Color
}

// current holds the active theme
var current = Default()

// Default returns the default high-contrast theme
func Default() Theme {
	return Theme{
		// Text - high contrast
		Primary:   White,
		Secondary: Gray,
		Muted:     DarkGray,
		Disabled:  DimGray,

		// Semantic - bright colors
		Accent:  Cyan,
		Success: Green,
		Warning: Yellow,
		Danger:  Red,
		Info:    Cyan,

		// Process types - bright & distinct
		WebServer:   Cyan,   // Cyan for web
		Database:    Green,  // Green for database
		Development: Yellow, // Yellow for dev tools
		System:      Gray,   // Gray for system
		Other:       Pink,   // Pink for other
	}
}

// Current returns the current theme
func Current() Theme {
	return current
}

// SetTheme sets the current theme
func SetTheme(t Theme) {
	current = t
}

// Styles - pre-configured lipgloss styles using the theme

// Text styles
func (t Theme) TextPrimary() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(t.Primary)
}

func (t Theme) TextSecondary() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(t.Secondary)
}

func (t Theme) TextMuted() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(t.Muted)
}

// Logo/Brand style
func (t Theme) Logo() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Cyan).Bold(true)
}

func (t Theme) LogoText() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(White).Bold(true)
}

// Header style for section titles
func (t Theme) Header() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Gray)
}

// Selection style - reverse video for visibility
func (t Theme) Selected() lipgloss.Style {
	return lipgloss.NewStyle().Reverse(true).Bold(true)
}

// Cursor indicator
func (t Theme) Cursor() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Cyan).Bold(true)
}

// AccentStyle for highlighted items
func (t Theme) AccentStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(t.Accent)
}

// InfoStyle for informational messages
func (t Theme) InfoStyle() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(t.Info)
}

// Status indicators
func (t Theme) Favorite() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Yellow)
}

func (t Theme) Watched() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Blue)
}

// Message styles
func (t Theme) SuccessMsg() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Green)
}

func (t Theme) ErrorMsg() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Red)
}

func (t Theme) WarningMsg() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Orange)
}

// Process type style
func (t Theme) ProcessType(ptype string) lipgloss.Style {
	var color lipgloss.Color
	switch ptype {
	case "WebServer":
		color = t.WebServer
	case "Database":
		color = t.Database
	case "Development":
		color = t.Development
	case "System":
		color = t.System
	default:
		color = t.Other
	}
	return lipgloss.NewStyle().Foreground(color)
}

// Help key style
func (t Theme) HelpKey() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Cyan)
}

func (t Theme) HelpDesc() lipgloss.Style {
	return lipgloss.NewStyle().Foreground(Gray)
}

// Dialog styles
func (t Theme) DialogBorder() lipgloss.Style {
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(Gray).
		Padding(1, 2)
}

func (t Theme) DialogDanger() lipgloss.Style {
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(Red).
		Padding(1, 2)
}
