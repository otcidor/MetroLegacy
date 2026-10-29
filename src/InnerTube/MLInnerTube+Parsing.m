#import "MLInnerTube.h"
#import "../Core/MLLibraryManager.h"

/*
 * Renderer parsing: JSON → MLYTItem / MLHomeSection / MLChip.
 * Mirrors Metrolist's innertube model parsing.
 */

extern id MLPath(id root, NSString *keyPath);

@implementation MLInnerTube (Parsing)

#pragma mark - Generic helpers

+ (NSArray *)allObjectsForKey:(NSString *)key inObject:(id)obj maxDepth:(NSUInteger)maxDepth
{
	// Breadth-first search for dicts containing `key`; returns the INNER values.
	NSMutableArray *result = [NSMutableArray array];
	NSMutableArray *queue = [NSMutableArray array];
	NSMutableArray *depths = [NSMutableArray array];
	if (obj) {
		[queue addObject:obj];
		[depths addObject:@0];
	}
	while (queue.count > 0) {
		id cur = queue[0];
		NSUInteger depth = [depths[0] unsignedIntegerValue];
		[queue removeObjectAtIndex:0];
		[depths removeObjectAtIndex:0];
		if (depth > maxDepth)
			continue;
		if ([cur isKindOfClass:[NSDictionary class]]) {
			NSDictionary *d = (NSDictionary *)cur;
			id hit = d[key];
			if (hit)
				[result addObject:hit];
			for (id k in d) {
				id v = d[k];
				if ([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSDictionary class]]) {
					[queue addObject:v];
					[depths addObject:@(depth + 1)];
				}
			}
		} else if ([cur isKindOfClass:[NSArray class]]) {
			for (id v in cur) {
				if ([v isKindOfClass:[NSArray class]] || [v isKindOfClass:[NSDictionary class]]) {
					[queue addObject:v];
					[depths addObject:@(depth + 1)];
				}
			}
		}
		if (result.count > 400)
			break; // safety
	}
	return result;
}

+ (NSString *)textFromRuns:(id)textObj
{
	if (!textObj)
		return nil;
	if ([textObj isKindOfClass:[NSString class]])
		return textObj;
	NSArray *runs = [textObj objectForKey:@"runs"];
	if (runs) {
		NSMutableString *s = [NSMutableString string];
		for (NSDictionary *run in runs) {
			NSString *t = run[@"text"];
			if ([t isKindOfClass:[NSString class]])
				[s appendString:t];
		}
		return s.length ? s : nil;
	}
	NSString *simple = [textObj objectForKey:@"simpleText"];
	if ([simple isKindOfClass:[NSString class]])
		return simple;
	return nil;
}

+ (NSString *)bestThumbnailUrl:(id)thumbObj
{
	if (!thumbObj)
		return nil;
	NSArray *thumbs = nil;
	if ([thumbObj isKindOfClass:[NSArray class]]) {
		thumbs = thumbObj;
	} else if ([thumbObj isKindOfClass:[NSDictionary class]]) {
		id direct = [thumbObj objectForKey:@"thumbnails"];
		if ([direct isKindOfClass:[NSArray class]]) {
			thumbs = direct;
		}
		if (!thumbs) {
			id mtr = [thumbObj objectForKey:@"musicThumbnailRenderer"];
			if ([mtr isKindOfClass:[NSDictionary class]]) {
				id t = [mtr objectForKey:@"thumbnail"];
				if ([t isKindOfClass:[NSDictionary class]] && [t[@"thumbnails"] isKindOfClass:[NSArray class]]) {
					thumbs = t[@"thumbnails"];
				} else if ([t isKindOfClass:[NSArray class]]) {
					thumbs = t;
				} else if ([mtr[@"thumbnails"] isKindOfClass:[NSArray class]]) {
					thumbs = mtr[@"thumbnails"];
				}
			}
		}
		if (!thumbs) {
			id tr = [thumbObj objectForKey:@"thumbnailRenderer"];
			if ([tr isKindOfClass:[NSDictionary class]]) {
				id mtr = [tr objectForKey:@"musicThumbnailRenderer"];
				if ([mtr isKindOfClass:[NSDictionary class]]) {
					id t = [mtr objectForKey:@"thumbnail"];
					if ([t isKindOfClass:[NSDictionary class]] && [t[@"thumbnails"] isKindOfClass:[NSArray class]]) {
						thumbs = t[@"thumbnails"];
					} else if ([mtr[@"thumbnails"] isKindOfClass:[NSArray class]]) {
						thumbs = mtr[@"thumbnails"];
					}
				}
			}
		}
		if (!thumbs) {
			id t = [thumbObj objectForKey:@"thumbnail"];
			if ([t isKindOfClass:[NSDictionary class]] && [t[@"thumbnails"] isKindOfClass:[NSArray class]]) {
				thumbs = t[@"thumbnails"];
			} else if ([t isKindOfClass:[NSArray class]]) {
				thumbs = t;
			}
		}
		if (!thumbs) {
			for (NSString *key in @[@"croppedSquareThumbnailRenderer", @"feedThumbnailRenderer"]) {
				id r = [thumbObj objectForKey:key];
				if ([r isKindOfClass:[NSDictionary class]]) {
					id t = [r objectForKey:@"thumbnail"];
					if ([t isKindOfClass:[NSDictionary class]] && [t[@"thumbnails"] isKindOfClass:[NSArray class]]) {
						thumbs = t[@"thumbnails"];
						break;
					} else if ([r[@"thumbnails"] isKindOfClass:[NSArray class]]) {
						thumbs = r[@"thumbnails"];
						break;
					}
				}
			}
		}
		if (!thumbs) {
			NSArray *found = [self allObjectsForKey:@"thumbnails" inObject:thumbObj maxDepth:4];
			for (id item in found) {
				if ([item isKindOfClass:[NSArray class]] && [(NSArray *)item count] > 0) {
					thumbs = item;
					break;
				}
			}
		}
	}
	if (![thumbs isKindOfClass:[NSArray class]] || thumbs.count == 0)
		return nil;
	NSString *bestCapped = nil;
	NSInteger bestCappedW = -1;
	NSString *fallback = nil;
	NSInteger fallbackW = NSIntegerMax;
	for (NSDictionary *t in thumbs) {
		if (![t isKindOfClass:[NSDictionary class]])
			continue;
		NSString *url = t[@"url"];
		NSInteger w = [t[@"width"] integerValue];
		if (![url isKindOfClass:[NSString class]] || !url.length)
			continue;
		if (w <= 544 && w > bestCappedW) {
			bestCappedW = w;
			bestCapped = url;
		} else if (w > 544 && w < fallbackW) {
			fallbackW = w;
			fallback = url;
		}
	}
	NSString *best = bestCapped ?: fallback;
	if ([best hasPrefix:@"//"])
		best = [@"https:" stringByAppendingString:best];
	return best;
}

static double MLDurationFromString(NSString *s)
{
	if (![s isKindOfClass:[NSString class]] || s.length == 0)
		return 0;
	static NSRegularExpression *regex = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		regex = [NSRegularExpression regularExpressionWithPattern:@"\\b\\d{1,2}[:.,]\\d{2}(?:[:.,]\\d{2})?\\b"
		                                                  options:0
		                                                    error:nil];
	});
	NSTextCheckingResult *match = [regex firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
	if (match) {
		NSString *matched = [s substringWithRange:match.range];
		NSCharacterSet *sepSet = [NSCharacterSet characterSetWithCharactersInString:@":.,"];
		NSArray *parts = [matched componentsSeparatedByCharactersInSet:sepSet];
		if (parts.count >= 2) {
			double total = 0;
			for (NSString *p in parts) {
				total = total * 60 + [p doubleValue];
			}
			return total;
		}
	}
	return 0;
}

static MLYTKind MLKindFromPageType(NSString *pageType)
{
	if (!pageType)
		return MLYTKindUnknown;
	if ([pageType rangeOfString:@"ALBUM"].length || [pageType rangeOfString:@"AUDIOBOOK"].length)
		return MLYTKindAlbum;
	if ([pageType rangeOfString:@"PLAYLIST"].length)
		return MLYTKindPlaylist;
	if ([pageType rangeOfString:@"ARTIST"].length || [pageType rangeOfString:@"USER_CHANNEL"].length)
		return MLYTKindArtist;
	if ([pageType rangeOfString:@"PODCAST"].length)
		return MLYTKindPodcast;
	return MLYTKindUnknown;
}

#pragma mark - Item renderers

+ (MLYTItem *)itemFromResponsiveListRenderer:(NSDictionary *)r
{
	MLYTItem *item = [[MLYTItem alloc] init];

	item.title = [self textFromRuns:MLPath(r, @"flexColumns.0.musicResponsiveListItemFlexColumnRenderer.text")];
	if (!item.title)
		item.title = [self textFromRuns:r[@"title"]];
	if (!item.title)
		item.title = [self textFromRuns:r[@"headline"]];

	NSDictionary *subCol = MLPath(r, @"flexColumns.1.musicResponsiveListItemFlexColumnRenderer.text");
	NSString *subtitle = [self textFromRuns:subCol];
	if (!subtitle)
		subtitle = [self textFromRuns:MLPath(r, @"fixedColumns.0.musicResponsiveListItemFixedColumnRenderer.text")];
	if (!subtitle)
		subtitle = [self textFromRuns:MLPath(r, @"fixedColumns.0.musicResponsiveListItemFlexColumnRenderer.text")];
	if (!subtitle)
		subtitle = [self textFromRuns:r[@"subtitle"]];
	item.subtitle = subtitle;

	NSMutableArray *artists = [NSMutableArray array];
	for (NSDictionary *col in r[@"flexColumns"] ?: @[]) {
		NSArray *runs = MLPath(col, @"musicResponsiveListItemFlexColumnRenderer.text.runs");
		for (NSDictionary *run in runs ?: @[]) {
			NSString *pageType = MLPath(run, @"navigationEndpoint.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType");
			NSString *bid = MLPath(run, @"navigationEndpoint.browseEndpoint.browseId");
			if ([bid hasPrefix:@"MPLAUC"])
				bid = [bid substringFromIndex:4];
			NSString *t = run[@"text"];
			if (([pageType isEqualToString:@"MUSIC_PAGE_TYPE_ARTIST"] || [pageType isEqualToString:@"MUSIC_PAGE_TYPE_LIBRARY_ARTIST"] || [bid hasPrefix:@"UC"]) && t.length) {
				if (![artists containsObject:t])
					[artists addObject:t];
				if (!item.artistBrowseId && bid.length)
					item.artistBrowseId = bid;
			} else if (([pageType isEqualToString:@"MUSIC_PAGE_TYPE_ALBUM"] || [bid hasPrefix:@"MPRE"]) && bid.length) {
				if (!item.albumBrowseId)
					item.albumBrowseId = bid;
			}
		}
	}
	if (!item.artistBrowseId || !item.albumBrowseId) {
		for (NSDictionary *be in [self allObjectsForKey:@"browseEndpoint" inObject:r[@"menu"] maxDepth:5]) {
			NSString *bid = be[@"browseId"];
			if ([bid isKindOfClass:[NSString class]]) {
				if ([bid hasPrefix:@"MPLAUC"])
					bid = [bid substringFromIndex:4];
				if (!item.artistBrowseId && [bid hasPrefix:@"UC"])
					item.artistBrowseId = bid;
				else if (!item.albumBrowseId && [bid hasPrefix:@"MPRE"])
					item.albumBrowseId = bid;
			}
		}
	}
	if (artists.count > 0)
		item.artists = artists;

	NSString *durationText = [self textFromRuns:MLPath(r, @"fixedColumns.0.musicResponsiveListItemFixedColumnRenderer.text")];
	if (!durationText)
		durationText = [self textFromRuns:MLPath(r, @"fixedColumns.0.musicResponsiveListItemFlexColumnRenderer.text")];
	if (!durationText)
		durationText = [self textFromRuns:MLPath(r, @"lengthText")];
	double dur = MLDurationFromString(durationText);
	if (dur <= 0) {
		for (NSDictionary *col in r[@"flexColumns"] ?: @[]) {
			NSArray *runs = MLPath(col, @"musicResponsiveListItemFlexColumnRenderer.text.runs");
			for (NSDictionary *run in runs ?: @[]) {
				double d = MLDurationFromString(run[@"text"]);
				if (d > 0) {
					dur = d;
					break;
				}
			}
			if (dur > 0) break;
		}
	}
	item.duration = dur;

	// thumbnail
	item.thumbnailUrl = [self bestThumbnailUrl:MLPath(r, @"thumbnail")];
	if (!item.thumbnailUrl)
		item.thumbnailUrl = [self bestThumbnailUrl:MLPath(r, @"thumbnail.musicThumbnailRenderer.thumbnail.thumbnails")];

	// navigation / kind / videoId
	NSString *pageType = MLPath(r, @"navigationEndpoint.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType");
	NSString *browseId = MLPath(r, @"navigationEndpoint.browseEndpoint.browseId");
	NSArray *titleRuns = MLPath(r, @"flexColumns.0.musicResponsiveListItemFlexColumnRenderer.text.runs");
	if (!browseId) {
		for (NSDictionary *run in titleRuns ?: @[]) {
			NSString *bid = MLPath(run, @"navigationEndpoint.browseEndpoint.browseId");
			if (bid) { browseId = bid; break; }
		}
	}
	if ([browseId hasPrefix:@"MPLAUC"]) {
		browseId = [browseId substringFromIndex:4];
	}
	MLYTKind kind = MLKindFromPageType(pageType);
	if (kind == MLYTKindUnknown && browseId) {
		if ([browseId hasPrefix:@"MPRE"] || [browseId rangeOfString:@"album" options:NSCaseInsensitiveSearch].length) {
			kind = MLYTKindAlbum;
		} else if ([browseId hasPrefix:@"VL"] || [browseId hasPrefix:@"PL"] || [browseId hasPrefix:@"RD"] || [browseId isEqualToString:@"LM"] || [browseId rangeOfString:@"playlist" options:NSCaseInsensitiveSearch].length || [browseId rangeOfString:@"liked" options:NSCaseInsensitiveSearch].length) {
			kind = MLYTKindPlaylist;
		} else if ([browseId hasPrefix:@"UC"] || [browseId hasPrefix:@"MPLA"]) {
			kind = MLYTKindArtist;
		}
	}

	NSString *directWatchPlaylistId = MLPath(r, @"navigationEndpoint.watchPlaylistEndpoint.playlistId");
	NSString *playlistItemVideoId = MLPath(r, @"playlistItemData.videoId");
	BOOL isContainerBrowse = (playlistItemVideoId.length == 0) &&
	                         (kind == MLYTKindAlbum || kind == MLYTKindPlaylist || kind == MLYTKindArtist || kind == MLYTKindPodcast ||
	                          (browseId.length > 0 && ([browseId hasPrefix:@"VL"] || [browseId hasPrefix:@"MPRE"] || [browseId hasPrefix:@"UC"] || [browseId hasPrefix:@"MPLA"] || [browseId hasPrefix:@"PL"] || [browseId hasPrefix:@"FE"])));

	// videoId: playlistItemData → title run watchEndpoint → overlay play button → navigationEndpoint → menu
	NSString *videoId = playlistItemVideoId;
	if (!videoId) {
		for (NSDictionary *run in titleRuns ?: @[]) {
			NSString *vid = MLPath(run, @"navigationEndpoint.watchEndpoint.videoId");
			if (vid) { videoId = vid; break; }
		}
	}
	if (!videoId) {
		NSString *vid = MLPath(r, @"navigationEndpoint.watchEndpoint.videoId");
		if (vid) videoId = vid;
	}
	if (!videoId && !isContainerBrowse) {
		NSString *vid = MLPath(r, @"overlay.musicItemThumbnailOverlayRenderer.content.musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint.videoId");
		if (vid) videoId = vid;
	}
	if (!videoId && !isContainerBrowse) {
		NSString *vid = MLPath(r, @"thumbnailOverlay.musicItemThumbnailOverlayRenderer.content.musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint.videoId");
		if (vid) videoId = vid;
	}
	if (!videoId && !isContainerBrowse) {
		for (NSDictionary *menu in [self allObjectsForKey:@"watchEndpoint" inObject:[r objectForKey:@"menu"] maxDepth:6]) {
			NSString *vid = [menu objectForKey:@"videoId"];
			if (vid) { videoId = vid; break; }
		}
	}
	if (!videoId && !isContainerBrowse) {
		for (NSDictionary *ep in [self allObjectsForKey:@"watchEndpoint" inObject:r maxDepth:6]) {
			NSString *vid = [ep objectForKey:@"videoId"];
			if (vid && [vid isKindOfClass:[NSString class]] && vid.length > 0) {
				videoId = vid;
				break;
			}
		}
	}
	if (isContainerBrowse) {
		videoId = nil;
	}
	item.videoId = videoId;

	NSString *mvt = MLPath(r, @"navigationEndpoint.watchEndpoint.musicVideoType");
	if (videoId && !browseId) {
		kind = (mvt && ![mvt isEqualToString:@"MUSIC_VIDEO_TYPE_ATV"]) ? MLYTKindVideo : MLYTKindSong;
	} else if (!browseId && !videoId && !isContainerBrowse) {
		for (NSDictionary *run in titleRuns ?: @[]) {
			NSString *vid = MLPath(run, @"navigationEndpoint.watchEndpoint.videoId");
			if (vid) {
				item.videoId = vid;
				kind = MLYTKindSong;
				break;
			}
		}
	}
	item.playlistId = directWatchPlaylistId;
	if (!item.playlistId) {
		item.playlistId = MLPath(r, @"overlay.musicItemThumbnailOverlayRenderer.content.musicPlayButtonRenderer.playNavigationEndpoint.watchPlaylistEndpoint.playlistId");
	}
	if (!item.playlistId && [browseId hasPrefix:@"VL"]) {
		item.playlistId = [browseId substringFromIndex:2];
	}
	if (!item.playlistId) {
		item.playlistId = MLPath(r, @"navigationEndpoint.watchEndpoint.playlistId");
	}
	if (kind == MLYTKindUnknown) {
		if (item.videoId.length > 0) {
			kind = MLYTKindSong;
		} else if (item.playlistId.length > 0 || [browseId hasPrefix:@"VL"]) {
			kind = MLYTKindPlaylist;
		}
	}
	item.kind = kind;
	item.browseId = browseId;

	// explicit badge
	for (NSDictionary *b in MLPath(r, @"badges") ?: @[]) {
		NSString *icon = MLPath(b, @"musicInlineBadgeRenderer.icon.iconType");
		if ([icon isEqualToString:@"MUSIC_EXPLICIT_BADGE"]) {
			item.explicit = YES;
			break;
		}
	}

	if (!item.title)
		return nil;
	if (!item.videoId.length && !item.browseId.length && !item.playlistId.length)
		return nil;

	// Real-time like status detection from YouTube Music response
	if (item.videoId.length > 0) {
		for (NSDictionary *lb in [self allObjectsForKey:@"likeButtonRenderer" inObject:r maxDepth:8]) {
			NSString *status = lb[@"likeStatus"];
			if ([status isKindOfClass:[NSString class]] && [status isEqualToString:@"LIKE"]) {
				NSString *targetVid = MLPath(lb, @"target.videoId") ?: item.videoId;
				if (targetVid.length > 0) {
					[[MLLibraryManager sharedManager] markSongId:targetVid asLiked:YES];
				}
				break;
			}
		}
	}

	return item;
}

+ (MLYTItem *)itemFromTwoRowRenderer:(NSDictionary *)r
{
	MLYTItem *item = [[MLYTItem alloc] init];
	item.title = [self textFromRuns:MLPath(r, @"title")];
	NSString *subtitle = [self textFromRuns:MLPath(r, @"subtitle")];
	item.subtitle = subtitle;
	for (NSDictionary *run in MLPath(r, @"subtitle.runs") ?: @[]) {
		NSString *bid = MLPath(run, @"navigationEndpoint.browseEndpoint.browseId");
		if ([bid isKindOfClass:[NSString class]]) {
			if ([bid hasPrefix:@"MPLAUC"])
				bid = [bid substringFromIndex:4];
			if (!item.artistBrowseId && [bid hasPrefix:@"UC"])
				item.artistBrowseId = bid;
			else if (!item.albumBrowseId && [bid hasPrefix:@"MPRE"])
				item.albumBrowseId = bid;
		}
	}
	item.thumbnailUrl = [self bestThumbnailUrl:MLPath(r, @"thumbnailRenderer")];
	if (!item.thumbnailUrl)
		item.thumbnailUrl = [self bestThumbnailUrl:MLPath(r, @"thumbnail")];

	NSString *pageType = MLPath(r, @"navigationEndpoint.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType");
	NSString *browseId = MLPath(r, @"navigationEndpoint.browseEndpoint.browseId");
	if ([browseId hasPrefix:@"MPLAUC"]) {
		browseId = [browseId substringFromIndex:4];
	}
	NSString *videoId = MLPath(r, @"navigationEndpoint.watchEndpoint.videoId");
	NSString *mvt = MLPath(r, @"navigationEndpoint.watchEndpoint.musicVideoType");
	NSString *playlistId = MLPath(r, @"thumbnailOverlay.musicItemThumbnailOverlayRenderer.content.musicPlayButtonRenderer.playNavigationEndpoint.watchPlaylistEndpoint.playlistId");
	if (!playlistId) {
		playlistId = MLPath(r, @"navigationEndpoint.watchPlaylistEndpoint.playlistId");
	}
	if (!playlistId && [browseId hasPrefix:@"VL"]) {
		playlistId = [browseId substringFromIndex:2];
	}

	MLYTKind kind = MLKindFromPageType(pageType);
	if (kind == MLYTKindUnknown && browseId) {
		if ([browseId hasPrefix:@"MPRE"] || [browseId rangeOfString:@"album" options:NSCaseInsensitiveSearch].length) {
			kind = MLYTKindAlbum;
		} else if ([browseId hasPrefix:@"VL"] || [browseId hasPrefix:@"PL"] || [browseId hasPrefix:@"RD"] || [browseId isEqualToString:@"LM"] || [browseId rangeOfString:@"playlist" options:NSCaseInsensitiveSearch].length || [browseId rangeOfString:@"liked" options:NSCaseInsensitiveSearch].length) {
			kind = MLYTKindPlaylist;
		} else if ([browseId hasPrefix:@"UC"] || [browseId hasPrefix:@"MPLA"]) {
			kind = MLYTKindArtist;
		}
	}
	if (kind == MLYTKindAlbum || kind == MLYTKindPlaylist || kind == MLYTKindArtist) {
		videoId = nil;
	} else if (videoId && !browseId) {
		kind = (mvt && ![mvt isEqualToString:@"MUSIC_VIDEO_TYPE_ATV"]) ? MLYTKindVideo : MLYTKindSong;
	} else if (kind == MLYTKindUnknown && videoId) {
		kind = MLYTKindSong;
	} else if (kind == MLYTKindUnknown && playlistId.length > 0) {
		kind = MLYTKindPlaylist;
	}
	item.kind = kind;
	item.videoId = videoId;
	item.browseId = browseId;
	item.playlistId = playlistId;

	if (subtitle.length > 0) {
		double d = MLDurationFromString(subtitle);
		if (d > 0)
			item.duration = d;
	}

	// explicit badge
	for (NSDictionary *b in MLPath(r, @"subtitleBadges") ?: @[]) {
		NSString *icon = MLPath(b, @"musicInlineBadgeRenderer.icon.iconType");
		if ([icon isEqualToString:@"MUSIC_EXPLICIT_BADGE"]) {
			item.explicit = YES;
			break;
		}
	}

	if (!item.title)
		return nil;
	if (!item.videoId.length && !item.browseId.length && !item.playlistId.length)
		return nil;
	return item;
}

+ (MLYTItem *)itemFromRenderer:(NSDictionary *)wrapper
{
	if (![wrapper isKindOfClass:[NSDictionary class]])
		return nil;
	NSDictionary *r = nil;
	if ((r = wrapper[@"musicResponsiveListItemRenderer"]))
		return [self itemFromResponsiveListRenderer:r];
	if ((r = wrapper[@"musicTwoRowItemRenderer"]))
		return [self itemFromTwoRowRenderer:r];
	if ((r = wrapper[@"playlistPanelVideoRenderer"])) {
		MLYTItem *item = [[MLYTItem alloc] init];
		item.kind = MLYTKindSong;
		item.videoId = r[@"videoId"] ?: MLPath(r, @"navigationEndpoint.watchEndpoint.videoId");
		item.title = [self textFromRuns:MLPath(r, @"title")];
		NSString *byline = [self textFromRuns:MLPath(r, @"longBylineText")] ?: [self textFromRuns:MLPath(r, @"shortBylineText")];
		item.subtitle = byline;
		NSMutableArray *artists = [NSMutableArray array];
		for (NSDictionary *run in MLPath(r, @"longBylineText.runs") ?: (MLPath(r, @"shortBylineText.runs") ?: @[])) {
			NSString *pageType = MLPath(run, @"navigationEndpoint.browseEndpoint.browseEndpointContextSupportedConfigs.browseEndpointContextMusicConfig.pageType");
			NSString *bid = MLPath(run, @"navigationEndpoint.browseEndpoint.browseId");
			NSString *t = run[@"text"];
			if (([pageType isEqualToString:@"MUSIC_PAGE_TYPE_ARTIST"] || [bid hasPrefix:@"UC"]) && t.length) {
				[artists addObject:t];
				if (!item.artistBrowseId && bid.length)
					item.artistBrowseId = bid;
			} else if (([pageType isEqualToString:@"MUSIC_PAGE_TYPE_ALBUM"] || [bid hasPrefix:@"MPRE"]) && bid.length) {
				if (!item.albumBrowseId)
					item.albumBrowseId = bid;
			}
		}
		if (!item.artistBrowseId || !item.albumBrowseId) {
			for (NSDictionary *be in [self allObjectsForKey:@"browseEndpoint" inObject:r[@"menu"] maxDepth:5]) {
				NSString *bid = be[@"browseId"];
				if ([bid isKindOfClass:[NSString class]]) {
					if (!item.artistBrowseId && [bid hasPrefix:@"UC"])
						item.artistBrowseId = bid;
					else if (!item.albumBrowseId && [bid hasPrefix:@"MPRE"])
						item.albumBrowseId = bid;
				}
			}
		}
		if (artists.count > 0)
			item.artists = artists;
		item.duration = MLDurationFromString([self textFromRuns:MLPath(r, @"lengthText")]);
		item.thumbnailUrl = [self bestThumbnailUrl:MLPath(r, @"thumbnail")];
		if (!item.title)
			return nil;

		if (item.videoId.length > 0) {
			for (NSDictionary *lb in [self allObjectsForKey:@"likeButtonRenderer" inObject:r maxDepth:8]) {
				NSString *status = lb[@"likeStatus"];
				if ([status isKindOfClass:[NSString class]] && [status isEqualToString:@"LIKE"]) {
					NSString *targetVid = MLPath(lb, @"target.videoId") ?: item.videoId;
					if (targetVid.length > 0) {
						[[MLLibraryManager sharedManager] markSongId:targetVid asLiked:YES];
					}
					break;
				}
			}
		}

		return item;
	}
	if ((r = wrapper[@"musicMultiRowListItemRenderer"])) {
		MLYTItem *item = [[MLYTItem alloc] init];
		item.kind = MLYTKindPodcast;
		item.videoId = MLPath(r, @"onTap.watchEndpoint.videoId");
		item.title = [self textFromRuns:MLPath(r, @"title")];
		item.subtitle = [self textFromRuns:MLPath(r, @"subtitle")];
		item.thumbnailUrl = [self bestThumbnailUrl:MLPath(r, @"thumbnailRenderer")];
		return item.title ? item : nil;
	}
	return nil;
}

+ (NSArray *)itemsFromContentsArray:(NSArray *)contents
{
	NSMutableArray *out = [NSMutableArray array];
	for (NSDictionary *wrapper in contents ?: @[]) {
		MLYTItem *it = [self itemFromRenderer:wrapper];
		if (it)
			[out addObject:it];
	}
	return out;
}

#pragma mark - Sections / chips / headers

+ (NSArray *)homeSectionsFromResponse:(NSDictionary *)response
{
	NSMutableArray *sections = [NSMutableArray array];

	// locate the main section list (single column tabs)
	id root = MLPath(response, @"contents");
	NSArray *sectionLists = [self allObjectsForKey:@"sectionListRenderer" inObject:root maxDepth:6];
	if (sectionLists.count == 0)
		sectionLists = [self allObjectsForKey:@"sectionListRenderer" inObject:response maxDepth:8];
	if (sectionLists.count == 0)
		return sections;

	// use the deepest first sectionList (tabs structure repeats; the real one contains shelves)
	NSDictionary *sectionList = sectionLists[0];
	NSArray *contents = [sectionList objectForKey:@"contents"] ?: @[];

	NSMutableArray *shelvesToProcess = [NSMutableArray array];
	for (NSDictionary *w in contents) {
		if (w[@"itemSectionRenderer"]) {
			NSArray *sub = MLPath(w, @"itemSectionRenderer.contents");
			if ([sub isKindOfClass:[NSArray class]]) {
				[shelvesToProcess addObjectsFromArray:sub];
				continue;
			}
		}
		[shelvesToProcess addObject:w];
	}

	for (NSDictionary *wrapper in shelvesToProcess) {
		NSDictionary *shelf = wrapper[@"musicCarouselShelfRenderer"];
		NSString *title = nil;
		NSString *moreBrowseId = nil;
		NSString *moreParams = nil;
		NSArray *items = nil;
		if (shelf) {
			title = [self textFromRuns:MLPath(shelf, @"header.musicCarouselShelfBasicHeaderRenderer.title")];
			if (!title)
				title = [self textFromRuns:MLPath(shelf, @"header.musicCarouselShelfHeaderRenderer.title")];
			if (!title)
				title = [self textFromRuns:MLPath(shelf, @"header.musicHeaderRenderer.title")];
			if (!title)
				title = [self textFromRuns:MLPath(shelf, @"title")];
			if (!title) {
				NSArray *titles = [self allObjectsForKey:@"title" inObject:[shelf objectForKey:@"header"] maxDepth:4];
				for (id t in titles) {
					NSString *ts = [self textFromRuns:t];
					if (ts.length) { title = ts; break; }
				}
			}

			NSDictionary *more = MLPath(shelf, @"header.musicCarouselShelfBasicHeaderRenderer.moreContentButton.browseEndpoint");
			if (!more)
				more = MLPath(shelf, @"header.musicCarouselShelfHeaderRenderer.moreContentButton.browseEndpoint");
			if (more) {
				NSString *bid = [more objectForKey:@"browseId"];
				NSString *p = [more objectForKey:@"params"];
				NSString *cont = MLPath(more, @"continuationCommand.token");
				if (bid)
					moreBrowseId = bid;
				if (p)
					moreParams = p;
				else if (cont)
					moreParams = cont;
			}
			items = [self itemsFromContentsArray:[shelf objectForKey:@"contents"]];
		} else if ((shelf = wrapper[@"musicShelfRenderer"])) {
			title = [self textFromRuns:MLPath(shelf, @"title")];
			items = [self itemsFromContentsArray:[shelf objectForKey:@"contents"]];
		} else if ((shelf = wrapper[@"gridRenderer"])) {
			title = [self textFromRuns:MLPath(shelf, @"header.gridHeaderRenderer.title")];
			items = [self itemsFromContentsArray:[shelf objectForKey:@"items"]];
		} else if ((shelf = wrapper[@"musicPlaylistShelfRenderer"])) {
			items = [self itemsFromContentsArray:[shelf objectForKey:@"contents"]];
		} else if (wrapper[@"musicDescriptionShelfRenderer"]) {
			continue; // description text, not items
		}
		if (items.count == 0)
			continue;
		if (!title)
			title = @"Recomendados";
		MLHomeSection *sec = [[MLHomeSection alloc] init];
		sec.title = title;
		sec.items = items;
		sec.moreBrowseId = moreBrowseId;
		sec.moreParams = moreParams;
		[sections addObject:sec];
	}
	return sections;
}

+ (NSArray *)chipsFromResponse:(NSDictionary *)response
{
	NSMutableArray *chips = [NSMutableArray array];
	NSArray *clouds = [self allObjectsForKey:@"chipCloudRenderer" inObject:response maxDepth:10];
	for (NSDictionary *cloud in clouds) {
		for (NSDictionary *wrapper in [cloud objectForKey:@"chips"] ?: @[]) {
			NSDictionary *chip = wrapper[@"chipCloudChipRenderer"];
			if (!chip)
				continue;
			NSString *title = [self textFromRuns:[chip objectForKey:@"text"]];
			NSString *params = MLPath(chip, @"navigationEndpoint.browseEndpoint.params");
			NSString *browseId = MLPath(chip, @"navigationEndpoint.browseEndpoint.browseId");
			BOOL selected = NO;
			id sel = [chip objectForKey:@"isSelected"];
			if (sel)
				selected = [sel boolValue];
			if (!title || !params)
				continue;
			MLChip *c = [[MLChip alloc] init];
			c.title = title;
			c.params = params;
			c.browseId = browseId;
			c.selected = selected;
			[chips addObject:c];
		}
	}
	return chips;
}

+ (NSString *)continuationFromResponseOrShelf:(id)obj
{
	if (!obj)
		return nil;
	// shelf.continuations[0].nextContinuationData.continuation
	NSArray *conts = MLPath(obj, @"continuations");
	for (NSDictionary *c in conts ?: @[]) {
		NSString *t = MLPath(c, @"nextContinuationData.continuation");
		if (t)
			return t;
	}
	// continuationContents.*.continuations
	for (NSString *ck in @[ @"musicPlaylistShelfContinuation", @"musicShelfContinuation", @"gridContinuation", @"sectionListContinuation" ]) {
		NSArray *cc = MLPath(obj, [NSString stringWithFormat:@"continuationContents.%@.continuations", ck]);
		for (NSDictionary *c in cc ?: @[]) {
			NSString *t = MLPath(c, @"nextContinuationData.continuation");
			if (t)
				return t;
		}
	}
	// contents[].continuationItemRenderer.continuationEndpoint.continuationCommand.token
	NSString *token = MLPath(obj, @"continuationItemRenderer.continuationEndpoint.continuationCommand.token");
	if (token)
		return token;
	for (NSDictionary *w in MLPath(obj, @"contents") ?: @[]) {
		token = MLPath(w, @"continuationItemRenderer.continuationEndpoint.continuationCommand.token");
		if (token)
			return token;
	}
	for (NSDictionary *w in MLPath(obj, @"items") ?: @[]) {
		token = MLPath(w, @"continuationItemRenderer.continuationEndpoint.continuationCommand.token");
		if (token)
			return token;
	}
	// onResponseReceivedActions[].appendContinuationItemsAction / appendAction
	for (NSDictionary *action in MLPath(obj, @"onResponseReceivedActions") ?: @[]) {
		for (NSDictionary *ci in MLPath(action, @"appendContinuationItemsAction.continuationItems") ?: @[]) {
			token = MLPath(ci, @"continuationItemRenderer.continuationEndpoint.continuationCommand.token");
			if (token)
				return token;
		}
		token = MLPath(action, @"appendContinuationItemsAction.continuationItemRenderer.continuationEndpoint.continuationCommand.token");
		if (token)
			return token;
		token = MLPath(action, @"appendAction.continuationItemRenderer.continuationEndpoint.continuationCommand.token");
		if (token)
			return token;
	}
	// If obj is a top-level InnerTube response, check nested continuation objects
	if ([obj isKindOfClass:[NSDictionary class]] && obj[@"responseContext"]) {
		for (NSDictionary *ncd in [self allObjectsForKey:@"nextContinuationData" inObject:obj maxDepth:12]) {
			NSString *t = ncd[@"continuation"];
			if ([t isKindOfClass:[NSString class]] && t.length > 0)
				return t;
		}
		for (NSDictionary *ccmd in [self allObjectsForKey:@"continuationCommand" inObject:obj maxDepth:12]) {
			NSString *t = ccmd[@"token"];
			if ([t isKindOfClass:[NSString class]] && t.length > 0)
				return t;
		}
	}
	return nil;
}

+ (NSUInteger)trackCountFromText:(NSString *)text
{
	if (!text.length) return 0;
	static NSRegularExpression *regexWithWord = nil;
	static NSRegularExpression *regexDigitsOnly = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSError *err = nil;
		regexWithWord = [NSRegularExpression regularExpressionWithPattern:@"([0-9][0-9\\.,\\s\u00a0\u202f]*)\\s*(?:cancion(?:es)?|canci[oó]n|songs?|titres?|temas?|pistas?|videos?|t[ií]tulos?)"
		                                                          options:NSRegularExpressionCaseInsensitive
		                                                            error:&err];
		regexDigitsOnly = [NSRegularExpression regularExpressionWithPattern:@"^[\\s\u00a0]*([0-9][0-9\\.,\\s\u00a0\u202f]*)[\\s\u00a0]*$"
		                                                            options:0
		                                                              error:&err];
	});
	NSTextCheckingResult *match = [regexWithWord firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
	if (!match) {
		match = [regexDigitsOnly firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
	}
	if (match && match.numberOfRanges > 1) {
		NSString *numStr = [text substringWithRange:[match rangeAtIndex:1]];
		NSMutableString *digitsOnly = [NSMutableString string];
		for (NSUInteger i = 0; i < numStr.length; i++) {
			unichar c = [numStr characterAtIndex:i];
			if (c >= '0' && c <= '9') {
				[digitsOnly appendFormat:@"%C", c];
			}
		}
		if (digitsOnly.length > 0) {
			return (NSUInteger)[digitsOnly longLongValue];
		}
	}
	return 0;
}

+ (NSUInteger)trackCountFromHeader:(NSDictionary *)header
{
	if (!header) return 0;
	if (header[@"trackCount"]) {
		return [header[@"trackCount"] unsignedIntegerValue];
	}
	NSUInteger tc = [self trackCountFromText:header[@"secondSubtitle"]];
	if (tc == 0) tc = [self trackCountFromText:header[@"subtitle"]];
	return tc;
}

+ (NSDictionary *)headerInfoFromResponse:(NSDictionary *)response
{
	NSDictionary *header = [response objectForKey:@"header"];
	if (![header isKindOfClass:[NSDictionary class]]) {
		NSArray *respHeaders = [self allObjectsForKey:@"musicResponsiveHeaderRenderer" inObject:response maxDepth:14];
		if (respHeaders.count > 0 && [respHeaders[0] isKindOfClass:[NSDictionary class]]) {
			header = @{ @"musicResponsiveHeaderRenderer" : respHeaders[0] };
		}
	}
	if (![header isKindOfClass:[NSDictionary class]]) {
		for (NSString *hKey in @[@"musicEditablePlaylistDetailHeaderRenderer", @"musicDetailHeaderRenderer", @"musicVisualHeaderRenderer", @"musicImmersiveHeaderRenderer"]) {
			NSArray *found = [self allObjectsForKey:hKey inObject:response maxDepth:14];
			if (found.count > 0 && [found[0] isKindOfClass:[NSDictionary class]]) {
				header = @{ hKey : found[0] };
				break;
			}
		}
	}
	if (![header isKindOfClass:[NSDictionary class]]) {
		NSArray *headers = [self allObjectsForKey:@"header" inObject:response maxDepth:14];
		for (id h in headers) {
			if ([h isKindOfClass:[NSDictionary class]]) {
				header = h;
				break;
			}
		}
	}
	if (![header isKindOfClass:[NSDictionary class]])
		return nil;

	NSMutableDictionary *info = [NSMutableDictionary dictionary];

	NSString *title = nil;
	NSString *subtitle = nil;
	NSString *secondSubtitle = nil;
	NSString *thumb = nil;
	NSString *description = nil;
	NSUInteger trackCount = 0;

	NSArray *names = @[
		@"musicDetailHeaderRenderer",
		@"musicResponsiveHeaderRenderer",
		@"musicEditablePlaylistDetailHeaderRenderer",
		@"musicImmersiveHeaderRenderer",
		@"musicVisualHeaderRenderer",
		@"musicHeaderRenderer",
	];
	for (NSString *name in names) {
		NSDictionary *r = [header objectForKey:name];
		if (!r)
			continue;
		title = [self textFromRuns:MLPath(r, @"title")];
		if (!title)
			title = [self textFromRuns:MLPath(r, @"playlistHeaderRenderer.title")];

		subtitle = [self textFromRuns:MLPath(r, @"subtitle")];
		if (!subtitle)
			subtitle = [self textFromRuns:MLPath(r, @"straplineTextOne")];
		if (!subtitle)
			subtitle = [self textFromRuns:MLPath(r, @"playlistHeaderRenderer.secondSubtitle")];

		secondSubtitle = [self textFromRuns:MLPath(r, @"secondSubtitle")];
		if (!secondSubtitle)
			secondSubtitle = [self textFromRuns:MLPath(r, @"playlistHeaderRenderer.secondSubtitle")];

		thumb = [self bestThumbnailUrl:MLPath(r, @"thumbnail")];
		if (!thumb)
			thumb = [self bestThumbnailUrl:MLPath(r, @"playlistHeaderRenderer.thumbnail")];

		description = [self textFromRuns:MLPath(r, @"description")];
		if (!description)
			description = [self textFromRuns:MLPath(r, @"description.musicDescriptionShelfRenderer.description")];

		trackCount = [self trackCountFromText:secondSubtitle];
		if (trackCount == 0) trackCount = [self trackCountFromText:subtitle];
		if (trackCount == 0 && r[@"itemCount"]) trackCount = [r[@"itemCount"] unsignedIntegerValue];
		if (trackCount == 0) {
			NSString *nvText = [self textFromRuns:MLPath(r, @"numVideosText")] ?: [self textFromRuns:MLPath(r, @"playlistHeaderRenderer.numVideosText")];
			if (nvText.length > 0) {
				trackCount = [self trackCountFromText:nvText];
			}
		}
		break;
	}
	if (title)
		info[@"title"] = title;
	if (subtitle)
		info[@"subtitle"] = subtitle;
	if (secondSubtitle)
		info[@"secondSubtitle"] = secondSubtitle;
	if (trackCount > 0)
		info[@"trackCount"] = @(trackCount);
	if (thumb)
		info[@"thumbnailUrl"] = thumb;
	if (description)
		info[@"description"] = description;
	return info.count ? info : nil;
}

@end
