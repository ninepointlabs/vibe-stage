.pragma library

// Nerd Font (Material Design) glyphs, by name. Checked present in the
// Nerd Fonts Omarchy ships.
var play = String.fromCodePoint(0xF040A)
var pause = String.fromCodePoint(0xF03E4)
var next = String.fromCodePoint(0xF04AD)
var previous = String.fromCodePoint(0xF04AE)
var note = String.fromCodePoint(0xF075A)
var volume = String.fromCodePoint(0xF057E)
var volumeOff = String.fromCodePoint(0xF0581)
var heart = String.fromCodePoint(0xF02D1)
var heartOutline = String.fromCodePoint(0xF02D5)
var thumbDown = String.fromCodePoint(0xF0511)
var shuffle = String.fromCodePoint(0xF049D)
var repeat = String.fromCodePoint(0xF0456)
var repeatOff = String.fromCodePoint(0xF0457)
var repeatOnce = String.fromCodePoint(0xF0458)
var plus = String.fromCodePoint(0xF0415)
var playNext = String.fromCodePoint(0xF0412)
var close = String.fromCodePoint(0xF0156)
var power = String.fromCodePoint(0xF0425)
var search = String.fromCodePoint(0xF0349)
var radio = String.fromCodePoint(0xF0439)
var up = String.fromCodePoint(0xF005D)
var down = String.fromCodePoint(0xF0045)
var back = String.fromCodePoint(0xF0141)
var album = String.fromCodePoint(0xF0025)
var artist = String.fromCodePoint(0xF0803)
var mic = String.fromCodePoint(0xF036F)
var gear = String.fromCodePoint(0xF0493)
var chevronLeft = String.fromCodePoint(0xF0141)
var chevronRight = String.fromCodePoint(0xF0142)
var sort = String.fromCodePoint(0xF04BA)        // md-sort

// Sources (Vibe Stage): the bar chip's small source mark and the panel tabs.
var ytmusic = String.fromCodePoint(0xF05C3)     // md-youtube
var pocketcasts = String.fromCodePoint(0xF0994) // md-podcast (the Pocket Casts plugin's own mark)
var audible = String.fromCodePoint(0xF02D9)     // md-headphones
var podcast = pocketcasts
var episode = String.fromCodePoint(0xF0386)     // md-music-circle (the Pocket Casts plugin's episode glyph)
var skipBack = String.fromCodePoint(0xF0D2A)    // md-rewind-10
var skipForward = String.fromCodePoint(0xF0D71) // md-fast-forward-30
var speed = String.fromCodePoint(0xF0F86)
var stop = String.fromCodePoint(0xF04DB)
var queue = String.fromCodePoint(0xF0415)
var queued = String.fromCodePoint(0xF012C)
var played = String.fromCodePoint(0xF0132)
var unplayed = String.fromCodePoint(0xF0131)
var refresh = String.fromCodePoint(0xF0450)
var signOut = String.fromCodePoint(0xF0343)

function sourceIcon(source) { return source === "podcasts" ? pocketcasts : source === "audible" ? audible : ytmusic }

function repeatIcon(mode) { return mode === "ONE" ? repeatOnce : mode === "ALL" ? repeat : repeatOff }
function volumeIcon(level, muted) { return muted || level === 0 ? volumeOff : volume }
