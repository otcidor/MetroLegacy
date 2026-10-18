#import "MLIcon.h"
#import "MLTheme.h"

/*
 * Material icon path data (24x24 viewport).
 * Source: Material Icons (https://fonts.google.com/icons), Apache 2.0.
 */
static NSDictionary *MLIconPathTable(void)
{
	static NSDictionary *paths = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		paths = @{
			// tab bar
			@"home" : @"M10 20v-6h4v6h5v-8h3L12 3 2 12h3v8z",
			@"home_outlined" : @"M12 5.69l5 4.5V18h-2v-6H9v6H7v-7.81l5-4.5M12 3L2 12h3v8h6v-6h2v6h6v-8h3L12 3z",
			@"search" : @"M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z",
			@"groups" : @"M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z",
			@"groups_outlined" : @"M9 13c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0-6c1.1 0 2 .9 2 2s-.9 2-2 2-2-.9-2-2 .9-2 2-2zm11 3c0 1.79-1.19 3.28-2.79 3.75.05.24.05.5.05.75 0 2.97-3.17 5.25-7.26 5.25S2.74 16.72 2.74 13.75c0-.25 0-.51.05-.75C1.19 13.28 0 11.79 0 10c0-2.21 1.79-4 4-4 1.04 0 1.98.4 2.7 1.05C7.79 6.4 8.84 6 10 6s2.21.4 3.3 1.05C14.02 6.4 14.96 6 16 6c2.21 0 4 1.79 4 4zm-11 8.24c1.53.53 3.06.53 4.59 0-1.29-.59-3.3-.59-4.59 0zM2.5 10c0 1.08.86 1.97 1.93 2.05.53-1.07 1.43-1.97 2.58-2.5C6.57 9.05 5.81 8.5 5 8.5c-1.38 0-2.5 1.12-2.5 2.5zm14 8.24c1.53.53 3.06.53 4.59 0-1.29-.59-3.3-.59-4.59 0zM16.5 8.5c-.81 0-1.57.55-2.01 1.05 1.15.53 2.05 1.43 2.58 2.5 1.07-.08 1.93-.97 1.93-2.05 0-1.38-1.12-2.5-2.5-2.5zm2.5 1.5c0 1.38-1.12 2.5-2.5 2.5-.81 0-1.57-.55-2.01-1.05.42-.19.79-.49 1.1-.85.36-.44.59-1 .59-1.6 0-.28-.03-.54-.09-.8.03 0 .06.01.09.01 1.66 0 2.82 1.34 2.82 2.79z",
			@"library_music" : @"M20 2H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-2 5h-3v5.5c0 1.38-1.12 2.5-2.5 2.5S10 13.88 10 12.5s1.12-2.5 2.5-2.5c.57 0 1.08.19 1.5.51V5h4v2zM4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6z",
			// player
			@"play_arrow" : @"M8 5v14l11-7z",
			@"pause" : @"M6 19h4V5H6v14zm8-14v14h4V5h-4z",
			@"skip_next" : @"M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z",
			@"skip_previous" : @"M6 6h2v12H6zm3.5 6l8.5 6V6z",
			@"favorite" : @"M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z",
			@"favorite_border" : @"M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3zm-4.4 15.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5 4 6.5 5.5 5 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87C13.46 5.99 14.96 5 16.5 5c2 0 3.5 1.5 3.5 3.5 0 2.89-3.14 5.74-7.9 10.05z",
			@"shuffle" : @"M10.59 9.17L5.41 4 4 5.41l5.17 5.17 1.42-1.41zM14.5 4l2.04 2.04L4 18.59 5.41 20 17.96 7.46 20 9.5V4h-5.5zm.33 9.41l-1.41 1.41 3.13 3.13L14.5 20H20v-5.5l-2.04 2.04-3.13-3.13z",
			@"repeat" : @"M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z",
			@"repeat_one" : @"M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4zm-4-2V9h-1l-2 1v1h1.5v4H13z",
			@"queue_music" : @"M15 6H3v2h12V6zm0 4H3v2h12v-2zm0 4H3v2h12v-2zm4-8v8.18c-.31-.11-.65-.18-1-.18-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3V6h-2z",
			@"delete" : @"M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z",
			// actions
			@"more_vert" : @"M12 8c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zm0 2c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm0 6c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z",
			@"arrow_back" : @"M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z",
			@"chevron_right" : @"M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z",
			@"close" : @"M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z",
			@"add" : @"M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z",
			@"playlist_play" : @"M19 9H2v2h17V9zm0-4H2v2h17V5zM2 15h13v-2H2v2zm15-2v6l5-3-5-3z",
			@"share" : @"M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92 1.61 0 2.92-1.31 2.92-2.92s-1.31-2.92-2.92-2.92z",
			@"person" : @"M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z",
			@"expand_more" : @"M16.59 8.59L12 13.17 7.41 8.59 6 10l6 6 6-6z",
			@"history" : @"M13 3c-4.97 0-9 4.03-9 9H1l3.89 3.89.07.14L8.9 12H6c0-3.87 3.13-7 7-7s7 3.13 7 7-3.13 7-7 7c-1.93 0-3.68-.79-4.94-2.06l-1.42 1.42C8.27 19.99 10.51 21 13 21c4.97 0 9-4.03 9-9s-4.03-9-9-9zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8H12z",
			@"vpn_key" : @"M12.65 10C11.83 7.67 9.61 6 7 6c-3.31 0-6 2.69-6 6s2.69 6 6 6c2.61 0 4.83-1.67 5.65-4H17v4h4v-4h2v-4H12.65zM7 14c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2z",
			@"content_paste" : @"M19 2h-4.18C14.4 0.84 13.3 0 12 0c-1.3 0-2.4.84-2.82 2H5c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm-7 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm7 18H5V4h2v3h10V4h2v16z",
			@"content_copy" : @"M16 1H4c-1.1 0-2 .9-2 2v14h2V3h12V1zm3 4H8c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h11c1.1 0 2-.9 2-2V7c0-1.1-.9-2-2-2zm0 16H8V7h11v14z",
			@"language" : @"M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zm6.93 6h-2.95c-.32-1.25-.78-2.45-1.38-3.56 1.84.63 3.37 1.91 4.33 3.56zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82c.43-1.43 1.08-2.76 1.91-3.96zM4.26 14C4.1 13.36 4 12.69 4 12s.1-1.36.26-2h3.38c-.08.66-.14 1.32-.14 2 0 .68.06 1.34.14 2H4.26zm.82 2h2.95c.32 1.25.78 2.45 1.38 3.56-1.84-.63-3.37-1.9-4.33-3.56zm2.95-8H5.08c.96-1.66 2.49-2.93 4.33-3.56C8.81 5.55 8.35 6.75 8.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-3.96h3.82c-.43 1.43-1.08 2.76-1.91 3.96zM14.34 14H9.66c-.09-.66-.16-1.32-.16-2 0-.68.07-1.35.16-2h4.68c.09.65.16 1.32.16 2 0 .68-.07 1.34-.16 2zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95c-.96 1.65-2.49 2.93-4.33 3.56zM16.36 14c.08-.66.14-1.32.14-2 0-.68-.06-1.34-.14-2h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z",
			@"translate" : @"M12.87 15.07l-2.54-2.51.03-.03c1.74-1.94 2.98-4.17 3.71-6.53H17V4h-7V2H8v2H1v1.99h11.17C11.5 7.92 10.44 9.75 9 11.35 8.07 10.32 7.3 9.19 6.69 8h-2c.73 1.63 1.73 3.17 2.98 4.56l-5.09 5.02L4 19l5-5 3.11 3.11.76-2.04zM18.5 10h-2L12 22h2l1.12-3h4.75L21 22h2l-4.5-12zm-2.62 7l1.62-4.33L19.12 17h-3.24z",
			@"equalizer" : @"M10 20h4V4h-4v16zm-6 0h4v-8H4v8zM16 9v11h4V9h-4z",
			@"radio" : @"M3.24 6.15C2.51 6.43 2 7.17 2 8v12c0 1.1.89 2 2 2h16c1.11 0 2-.9 2-2V8c0-1.11-.89-2-2-2H8.3l8.26-3.34L15.88 1 3.24 6.15zM7 20c-1.66 0-3-1.34-3-3s1.34-3 3-3 3 1.34 3 3-1.34 3-3 3zm13-8h-2v-2h-2v2H4V8h16v4z",
			@"music_note" : @"M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z",
			@"download" : @"M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z",
			@"download_done" : @"M5 18h14v2H5v-2zm4.6-2.7L5 10.7l2-1.9 2.6 2.6L17 4l2 2-9.4 9.3z",
			@"sync" : @"M12 4V1L8 5l4 4V6c3.31 0 6 2.69 6 6 0 1.01-.25 1.97-.7 2.8l1.46 1.46C19.54 15.03 20 13.57 20 12c0-4.42-3.58-8-8-8zm0 14c-3.31 0-6-2.69-6-6 0-1.01.25-1.97.7-2.8L5.24 7.74C4.46 8.97 4 10.43 4 12c0 4.42 3.58 8 8 8v3l4-4-4-4v3z",
			@"cached" : @"M19 8l-4 4h3c0 3.31-2.69 6-6 6-1.01 0-1.97-.25-2.8-.7l-1.46 1.46C8.97 19.54 10.43 20 12 20c4.42 0 8-3.58 8-8h3l-4-4zM6 12c0-3.31 2.69-6 6-6 1.01 0 1.97.25 2.8.7l1.46-1.46C15.03 4.46 13.57 4 12 4c-4.42 0-8 3.58-8 8H1l4 4 4-4H6z",
			@"album" : @"M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 14.5c-2.49 0-4.5-2.01-4.5-4.5S9.51 7.5 12 7.5s4.5 2.01 4.5 4.5-2.01 4.5-4.5 4.5zm0-5.5c-.55 0-1 .45-1 1s.45 1 1 1 1-.45 1-1-.45-1-1-1z",
			@"playlist_add" : @"M14 10H2v2h12v-2zm0-4H2v2h12V6zm4 8v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zM2 16h8v-2H2v2z",
			@"lyrics" : @"M15 1H3c-1.1 0-2 .9-2 2v13c0 1.1.9 2 2 2h5v4l5-4h4c1.1 0 2-.9 2-2V3c0-1.1-.9-2-2-2zm-3 12H6v-2h6v2zm3-3H6V8h9v2zm0-3H6V5h9v2z",
			@"bedtime" : @"M12.3 2a10 10 0 0 0-1.9 19.8 10 10 0 0 0 10.9-10.9A10.02 10.02 0 0 0 12.3 2z",
			@"timer" : @"M15 1H9v2h6V1zm-4 13h2V8h-2v6zm8.03-6.61l1.42-1.42c-.43-.51-.9-.99-1.41-1.41l-1.42 1.42C16.07 4.74 14.12 4 12 4c-4.97 0-9 4.03-9 9s4.02 9 9 9 9-4.03 9-9c0-2.12-.74-4.07-1.97-5.61zM12 20c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z",
			@"devices" : @"M4 6h18V4H4c-1.1 0-2 .9-2 2v11H0v3h14v-3H4V6zm19 2h-6c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h6c.55 0 1-.45 1-1V9c0-.55-.45-1-1-1zm-1 9h-4v-7h4v7z",
			@"block" : @"M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.42 0-8-3.58-8-8 0-1.85.63-3.55 1.69-4.9L16.9 18.31C15.55 19.37 13.85 20 12 20zm6.31-3.1L7.1 5.69C8.45 4.63 10.15 4 12 4c4.42 0 8 3.58 8 8 0 1.85-.63 3.55-1.69 4.9z",
			@"sort" : @"M3 18h6v-2H3v2zM3 6v2h18V6H3zm0 7h12v-2H3v2z",
			@"north_west" : @"M5 15h2V8.41L18.59 20 20 18.59 8.41 7H15V5H5v10z",
			@"trending_up" : @"M16 6l2.29 2.29-4.88 4.88-4-4L2 16.59 3.41 18l6-6 4 4 6.3-6.29L22 12V6z",
			@"grid_view" : @"M3 3v8h8V3H3zm6 6H5V5h4v4zm-6 4v8h8v-8H3zm6 6H5v-4h4v4zm4-16v8h8V3h-8zm6 6h-4V5h4v4zm-6 4v8h8v-8h-8zm6 6h-4v-4h4v4z",
			@"view_list" : @"M4 14h4v-4H4v4zm0 5h4v-4H4v4zM4 9h4V5H4v4zm5 5h12v-4H9v4zm0 5h12v-4H9v4zM9 5v4h12V5H9z",
			@"casino" : @"M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM7.25 18.25c-.69 0-1.25-.56-1.25-1.25s.56-1.25 1.25-1.25 1.25.56 1.25 1.25-.56 1.25-1.25 1.25zm0-9.5c-.69 0-1.25-.56-1.25-1.25S6.56 6.25 7.25 6.25s1.25.56 1.25 1.25-.56 1.25-1.25 1.25zm4.75 4.75c-.69 0-1.25-.56-1.25-1.25s.56-1.25 1.25-1.25 1.25.56 1.25 1.25-.56 1.25-1.25 1.25zm4.75 4.75c-.69 0-1.25-.56-1.25-1.25s.56-1.25 1.25-1.25 1.25.56 1.25 1.25-.56 1.25-1.25 1.25zm0-9.5c-.69 0-1.25-.56-1.25-1.25s.56-1.25 1.25-1.25 1.25.56 1.25 1.25-.56 1.25-1.25 1.25z",
			@"palette" : @"M12 2C6.49 2 2 6.49 2 12s4.49 10 10 10c1.38 0 2.5-1.12 2.5-2.5 0-.61-.23-1.2-.64-1.67-.08-.1-.13-.21-.13-.33 0-.28.22-.5.5-.5H16c3.31 0 6-2.69 6-6 0-4.96-4.49-9-10-9zm-5.5 9c-.83 0-1.5-.67-1.5-1.5S5.67 8 6.5 8s1.5.67 1.5 1.5S7.33 11 6.5 11zm3-4C8.67 7 8 6.33 8 5.5S8.67 4 9.5 4s1.5.67 1.5 1.5S10.33 7 9.5 7zm5 0c-.83 0-1.5-.67-1.5-1.5S13.67 4 14.5 4s1.5.67 1.5 1.5S15.33 7 14.5 7zm3 4c-.83 0-1.5-.67-1.5-1.5S16.67 8 17.5 8s1.5.67 1.5 1.5-.67 1.5-1.5 1.5z",
			@"dark_mode" : @"M12.3 2a10 10 0 0 0-1.9 19.8 10 10 0 0 0 10.9-10.9A10.02 10.02 0 0 0 12.3 2z",
		};
	});
	return paths;
}

#pragma mark - SVG path parsing

static CGPoint MLXfm(const CGFloat *m, CGFloat x, CGFloat y)
{
	return CGPointMake(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]);
}

// SVG endpoint-parameterization arc, emitted as cubic beziers (SVG spec F.6.5).
static void MLEmitArc(UIBezierPath *path, CGPoint cur, CGPoint end,
					  CGFloat rx, CGFloat ry, CGFloat xrotDeg,
					  BOOL largeArc, BOOL sweep)
{
	if (rx == 0.0f || ry == 0.0f) {
		[path addLineToPoint:end];
		return;
	}
	rx = (CGFloat)fabs(rx);
	ry = (CGFloat)fabs(ry);
	CGFloat phi = xrotDeg * (CGFloat)M_PI / 180.0f;
	CGFloat cosPhi = cosf(phi), sinPhi = sinf(phi);
	CGFloat dx2 = (cur.x - end.x) / 2.0f, dy2 = (cur.y - end.y) / 2.0f;
	CGFloat x1p = cosPhi * dx2 + sinPhi * dy2;
	CGFloat y1p = -sinPhi * dx2 + cosPhi * dy2;

	CGFloat lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry);
	if (lambda > 1.0f) {
		CGFloat s = sqrtf(lambda);
		rx *= s;
		ry *= s;
	}

	CGFloat sign = (largeArc != sweep) ? 1.0f : -1.0f;
	CGFloat num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p;
	CGFloat den = rx * rx * y1p * y1p + ry * ry * x1p * x1p;
	if (num < 0.0f) num = 0.0f;
	CGFloat co = sign * sqrtf(num / (den ?: 1.0f));
	CGFloat cxp = co * (rx * y1p / ry);
	CGFloat cyp = co * (-ry * x1p / rx);
	CGFloat cx = cosPhi * cxp - sinPhi * cyp + (cur.x + end.x) / 2.0f;
	CGFloat cy = sinPhi * cxp + cosPhi * cyp + (cur.y + end.y) / 2.0f;

	CGFloat ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
	CGFloat vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
	CGFloat th0 = atan2f(uy, ux);
	CGFloat dth = atan2f(vy, vx) - th0;
	if (!sweep && dth > 0.0f)
		dth -= 2.0f * (CGFloat)M_PI;
	else if (sweep && dth < 0.0f)
		dth += 2.0f * (CGFloat)M_PI;

	int segments = (int)ceilf((float)fabs(dth) / ((float)M_PI / 2.0f));
	if (segments < 1) segments = 1;
	CGFloat delta = dth / segments;
	CGFloat alpha = (4.0f / 3.0f) * tanf(delta / 4.0f);

	CGFloat m[6] = { cosPhi, sinPhi, -sinPhi, cosPhi, cx, cy };
	for (int i = 0; i < segments; i++) {
		CGFloat t0 = th0 + delta * i;
		CGFloat t1 = t0 + delta;
		CGPoint p0 = MLXfm(m, rx * cosf(t0), ry * sinf(t0));
		CGPoint d0 = MLXfm(m, -rx * sinf(t0) * alpha, ry * cosf(t0) * alpha);
		CGPoint p1 = MLXfm(m, rx * cosf(t1), ry * sinf(t1));
		CGPoint d1 = MLXfm(m, -rx * sinf(t1) * alpha, ry * cosf(t1) * alpha);
		if (i == 0)
			[path addLineToPoint:p0]; // sit on arc start (cur may differ slightly)
		[path addCurveToPoint:p1
				controlPoint1:CGPointMake(p0.x + d0.x, p0.y + d0.y)
				controlPoint2:CGPointMake(p1.x - d1.x, p1.y - d1.y)];
	}
}

static UIBezierPath *MLParseSVGPath(NSString *d)
{
	UIBezierPath *path = [UIBezierPath bezierPath];
	if (!d || d.length == 0)
		return path;

	NSUInteger i = 0, len = d.length;
	CGPoint cur = CGPointZero, start = CGPointZero, ctrl = CGPointZero;
	unichar cmd = 0;

	NSMutableArray *nums = [NSMutableArray array];

#define ML_RESET_NUMS() [nums removeAllObjects]
#define MLN(idx) ((CGFloat)[nums count] > (idx) ? [[nums objectAtIndex:(idx)] doubleValue] : 0.0f)

	while (i < len) {
		unichar c = [d characterAtIndex:i];
		if (c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\r') {
			i++;
			continue;
		}
		if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
			cmd = c;
			i++;
			ML_RESET_NUMS();
			while (i < len) {
				unichar ch = [d characterAtIndex:i];
				if ((ch >= '0' && ch <= '9') || ch == '-' || ch == '+' || ch == '.') {
					NSMutableString *tok = [NSMutableString string];
					if (ch == '-' || ch == '+') {
						[tok appendFormat:@"%C", ch];
						i++;
					}
					BOOL dotSeen = NO;
					while (i < len) {
						unichar dc = [d characterAtIndex:i];
						if (dc >= '0' && dc <= '9') {
							[tok appendFormat:@"%C", dc];
							i++;
						} else if (dc == '.' && !dotSeen) {
							dotSeen = YES;
							[tok appendFormat:@"%C", dc];
							i++;
						} else {
							break;
						}
					}
					[nums addObject:[NSNumber numberWithDouble:tok.doubleValue]];
				} else if (ch == ' ' || ch == ',' || ch == '\n' || ch == '\t' || ch == '\r') {
					i++;
				} else {
					break;
				}
			}

			BOOL rel = (cmd >= 'a' && cmd <= 'z');
			NSUInteger consumed = 0;
			switch (cmd) {
				case 'M': case 'm': {
					while (consumed + 1 < nums.count) {
						CGPoint p = CGPointMake(MLN(consumed), MLN(consumed + 1));
						BOOL firstPair = (consumed == 0);
						consumed += 2;
						if (rel) { p.x += cur.x; p.y += cur.y; }
						if (firstPair) {
							[path moveToPoint:p];
							start = p;
						} else {
							[path addLineToPoint:p];
						}
						cur = p;
					}
					break;
				}
				case 'L': case 'l': {
					while (consumed + 1 < nums.count) {
						CGPoint p = CGPointMake(MLN(consumed), MLN(consumed + 1));
						consumed += 2;
						if (rel) { p.x += cur.x; p.y += cur.y; }
						[path addLineToPoint:p];
						cur = p;
					}
					break;
				}
				case 'H': case 'h': {
					while (consumed < nums.count) {
						CGFloat x = MLN(consumed); consumed++;
						if (rel) x += cur.x;
						cur = CGPointMake(x, cur.y);
						[path addLineToPoint:cur];
					}
					break;
				}
				case 'V': case 'v': {
					while (consumed < nums.count) {
						CGFloat y = MLN(consumed); consumed++;
						if (rel) y += cur.y;
						cur = CGPointMake(cur.x, y);
						[path addLineToPoint:cur];
					}
					break;
				}
				case 'C': case 'c': {
					while (consumed + 5 < nums.count) {
						CGPoint p1 = CGPointMake(MLN(consumed), MLN(consumed + 1));
						CGPoint p2 = CGPointMake(MLN(consumed + 2), MLN(consumed + 3));
						CGPoint p3 = CGPointMake(MLN(consumed + 4), MLN(consumed + 5));
						consumed += 6;
						if (rel) {
							p1.x += cur.x; p1.y += cur.y;
							p2.x += cur.x; p2.y += cur.y;
							p3.x += cur.x; p3.y += cur.y;
						}
						[path addCurveToPoint:p3 controlPoint1:p1 controlPoint2:p2];
						ctrl = p2;
						cur = p3;
					}
					break;
				}
				case 'S': case 's': {
					while (consumed + 3 < nums.count) {
						CGPoint p1 = CGPointMake(2 * cur.x - ctrl.x, 2 * cur.y - ctrl.y);
						CGPoint p2 = CGPointMake(MLN(consumed), MLN(consumed + 1));
						CGPoint p3 = CGPointMake(MLN(consumed + 2), MLN(consumed + 3));
						consumed += 4;
						if (rel) {
							p2.x += cur.x; p2.y += cur.y;
							p3.x += cur.x; p3.y += cur.y;
						}
						[path addCurveToPoint:p3 controlPoint1:p1 controlPoint2:p2];
						ctrl = p2;
						cur = p3;
					}
					break;
				}
				case 'Q': case 'q': {
					while (consumed + 3 < nums.count) {
						CGPoint p1 = CGPointMake(MLN(consumed), MLN(consumed + 1));
						CGPoint p2 = CGPointMake(MLN(consumed + 2), MLN(consumed + 3));
						consumed += 4;
						if (rel) {
							p1.x += cur.x; p1.y += cur.y;
							p2.x += cur.x; p2.y += cur.y;
						}
						[path addQuadCurveToPoint:p2 controlPoint:p1];
						ctrl = p1;
						cur = p2;
					}
					break;
				}
				case 'T': case 't': {
					while (consumed + 1 < nums.count) {
						CGPoint p1 = CGPointMake(2 * cur.x - ctrl.x, 2 * cur.y - ctrl.y);
						CGPoint p2 = CGPointMake(MLN(consumed), MLN(consumed + 1));
						consumed += 2;
						if (rel) { p2.x += cur.x; p2.y += cur.y; }
						[path addQuadCurveToPoint:p2 controlPoint:p1];
						ctrl = p1;
						cur = p2;
					}
					break;
				}
				case 'A': case 'a': {
					while (consumed + 6 < nums.count) {
						CGFloat rx = MLN(consumed), ry = MLN(consumed + 1);
						CGFloat rot = MLN(consumed + 2);
						BOOL largeArc = MLN(consumed + 3) != 0.0f;
						BOOL sweep = MLN(consumed + 4) != 0.0f;
						CGPoint p = CGPointMake(MLN(consumed + 5), MLN(consumed + 6));
						consumed += 7;
						if (rel) { p.x += cur.x; p.y += cur.y; }
						MLEmitArc(path, cur, p, rx, ry, rot, largeArc, sweep);
						cur = p;
					}
					break;
				}
				case 'Z': case 'z': {
					[path closePath];
					cur = start;
					break;
				}
			}
		} else {
			i++;
		}
	}
	return path;
}

@implementation MLIcon

+ (NSString *)resolvedName:(NSString *)name variant:(int)variant
{
	NSString *key = name;
	if (variant == MLIconVariantOutlined) {
		NSString *outlined = [name stringByAppendingString:@"_outlined"];
		if ([MLIconPathTable() objectForKey:outlined])
			key = outlined;
	}
	return key;
}

+ (UIBezierPath *)path:(NSString *)name variant:(int)variant inRect:(CGRect)rect
{
	NSString *key = [self resolvedName:name variant:variant];
	NSString *d = [MLIconPathTable() objectForKey:key];
	if (!d)
		d = [MLIconPathTable() objectForKey:name];
	if (!d)
		return [UIBezierPath bezierPath];

	UIBezierPath *p24 = MLParseSVGPath(d);
	if ([p24 isEmpty])
		return p24;

	CGFloat s = MIN(rect.size.width / 24.0f, rect.size.height / 24.0f);
	CGFloat tx = rect.origin.x + (rect.size.width - 24.0f * s) / 2.0f;
	CGFloat ty = rect.origin.y + (rect.size.height - 24.0f * s) / 2.0f;
	CGAffineTransform xf = CGAffineTransformMake(s, 0.0f, 0.0f, s, tx, ty);
	UIBezierPath *out = [p24 copy];
	[out applyTransform:xf];
	return out;
}

+ (UIImage *)icon:(NSString *)name variant:(int)variant size:(CGFloat)size color:(UIColor *)color
{
	NSString *key = [NSString stringWithFormat:@"%@|%d|%.0f|%@", [self resolvedName:name variant:variant], variant, size, color];
	static NSCache *cache = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ cache = [[NSCache alloc] init]; });
	UIImage *hit = [cache objectForKey:key];
	if (hit)
		return hit;

	UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0f);
	UIBezierPath *p = [self path:name variant:variant inRect:CGRectMake(0, 0, size, size)];
	[color setFill];
	[p fill];
	UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	if (img)
		[cache setObject:img forKey:key];
	return img;
}

+ (UIImage *)icon:(NSString *)name size:(CGFloat)size color:(UIColor *)color
{
	return [self icon:name variant:MLIconVariantFilled size:size color:color];
}

@end
