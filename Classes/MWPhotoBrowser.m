//
//  MWPhotoBrowser.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import "MWPhotoBrowser.h"
#import "MWZoomingScrollView.h"
#import <QuartzCore/QuartzCore.h>

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

#define PADDING                 10
#define PAGE_INDEX_TAG_OFFSET   1000
#define PAGE_INDEX(page)        ([(page) tag] - PAGE_INDEX_TAG_OFFSET)

@interface MWPhotoBrowser ()

// Private Properties
@property (nonatomic, retain) UIColor *previousNavBarTintColor;
@property (nonatomic, retain) UIImage *navigationBarBackgroundImageDefault, *navigationBarBackgroundImageLandscapePhone;

// Private Methods

// Layout
- (void)performLayout;

// Paging
- (void)tilePages;
- (BOOL)isDisplayingPageForIndex:(NSUInteger)index;
- (MWZoomingScrollView *)pageDisplayedAtIndex:(NSUInteger)index;
- (MWZoomingScrollView *)pageDisplayingPhoto:(MWPhoto *)photo;
- (MWZoomingScrollView *)dequeueRecycledPage;
- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index;
- (void)didStartViewingPageAtIndex:(NSUInteger)index;

// Frames
- (CGRect)frameForPagingScrollView;
- (CGRect)frameForPageAtIndex:(NSUInteger)index;
- (CGSize)contentSizeForPagingScrollView;
- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index;
- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation;
- (CGRect)frameForCaptionView:(MWCaptionView *)captionView atIndex:(NSUInteger)index;

// Navigation
- (void)updateNavigation;
- (void)jumpToPageAtIndex:(NSUInteger)index;
- (void)gotoPreviousPage;
- (void)gotoNextPage;

// Controls
- (void)cancelControlHiding;
- (void)hideControlsAfterDelay;
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated;
- (void)toggleControls;
- (BOOL)areControlsHidden;

// Data
- (NSUInteger)numberOfPhotos;
- (MWPhoto *)photoAtIndex:(NSUInteger)index;
- (UIImage *)imageForPhoto:(MWPhoto *)photo;
- (void)loadAdjacentPhotosIfNecessary:(MWPhoto *)photo;
- (void)releaseAllUnderlyingPhotos;

@end

// Handle depreciations and supress hide warnings
@interface UIApplication (DepreciationWarningSuppresion)
- (void)setStatusBarHidden:(BOOL)hidden animated:(BOOL)animated;
@end

// MWPhotoBrowser
@implementation MWPhotoBrowser

@synthesize delegate = _delegate;
@synthesize previousNavBarTintColor = _previousNavBarTintColor;
@synthesize navigationBarBackgroundImageDefault = _navigationBarBackgroundImageDefault,
navigationBarBackgroundImageLandscapePhone = _navigationBarBackgroundImageLandscapePhone;

#pragma mark - NSObject

- (id)init {
    if ((self = [super init])) {
        
        // Defaults
        self.wantsFullScreenLayout = YES;
        self.hidesBottomBarWhenPushed = YES;
        _photoCount = NSNotFound;
		_currentPageIndex = 0;
		_performingLayout = NO; // Reset on view did appear
		_rotating = NO;
        _viewIsVisible = NO;
        _visiblePages = [[NSMutableSet alloc] init];
        _recycledPages = [[NSMutableSet alloc] init];
        _photos = [[NSMutableArray alloc] init];
        _loadAdjacentWhenCurrentPhotoHasLoaded = NO;
        
    }
    return self;
}

- (id)initWithDelegate:(id <MWPhotoBrowserDelegate>)delegate {
    if ((self = [self init])) {
        self.delegate = delegate;
	}
	return self;
}

- (id)initWithPhotos:(NSArray *)photosArray {
	if ((self = [self init])) {
		_depreciatedPhotoData = [photosArray retain];
	}
	return self;
}

- (void)dealloc {
    [_previousNavBarTintColor release];
    [_navigationBarBackgroundImageDefault release];
    [_navigationBarBackgroundImageLandscapePhone release];
	[_pagingScrollView release];
	[_visiblePages release];
	[_recycledPages release];
	[_toolbar release];
	[_previousButton release];
	[_nextButton release];
  	[_depreciatedPhotoData release];
    [self releaseAllUnderlyingPhotos];
    [_photos release];
    [super dealloc];
}

- (void)releaseAllUnderlyingPhotos {
    for (id p in _photos) { if (p != [NSNull null]) [p releasePhoto]; } // Release photos
}

- (void)didReceiveMemoryWarning {
	
	// Release any cached data, images, etc that aren't in use.
    [self releaseAllUnderlyingPhotos];
	[_recycledPages removeAllObjects];
	
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
}

#pragma mark - View Loading

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
	
	// View
	self.view.backgroundColor = [UIColor blackColor];
	
	// Setup paging scrolling view
	CGRect pagingScrollViewFrame = [self frameForPagingScrollView];
	_pagingScrollView = [[UIScrollView alloc] initWithFrame:pagingScrollViewFrame];
	_pagingScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_pagingScrollView.pagingEnabled = YES;
	_pagingScrollView.delegate = self;
	_pagingScrollView.showsHorizontalScrollIndicator = NO;
	_pagingScrollView.showsVerticalScrollIndicator = NO;
	_pagingScrollView.backgroundColor = [UIColor blackColor];
    _pagingScrollView.contentSize = [self contentSizeForPagingScrollView];
	[self.view addSubview:_pagingScrollView];
	
    // Toolbar
    _toolbar = [[UIToolbar alloc] initWithFrame:[self frameForToolbarAtOrientation:self.interfaceOrientation]];
    _toolbar.tintColor = nil;
    if ([[UIToolbar class] respondsToSelector:@selector(appearance)]) {
        [_toolbar setBackgroundImage:nil forToolbarPosition:UIToolbarPositionAny barMetrics:UIBarMetricsDefault];
        [_toolbar setBackgroundImage:nil forToolbarPosition:UIToolbarPositionAny barMetrics:UIBarMetricsLandscapePhone];
    }
    _toolbar.barStyle = UIBarStyleBlackTranslucent;
    _toolbar.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;

    // Toolbar Items
    _previousButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"UIBarButtonItemArrowLeft.png"] style:UIBarButtonItemStylePlain target:self action:@selector(gotoPreviousPage)];
    _nextButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"UIBarButtonItemArrowRight.png"] style:UIBarButtonItemStylePlain target:self action:@selector(gotoNextPage)];
    
    // Update
    [self reloadData];
    
	// Super
    [super viewDidLoad];
	
}

- (void)performLayout {
    
    // Setup
    _performingLayout = YES;
    NSUInteger numberOfPhotos = [self numberOfPhotos];
    
	// Setup pages
    [_visiblePages removeAllObjects];
    [_recycledPages removeAllObjects];
    
    // Toolbar
    if (numberOfPhotos > 1) {
        [self.view addSubview:_toolbar];
    } else {
        [_toolbar removeFromSuperview];
    }
    
    // Toolbar items & navigation
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    NSMutableArray *items = [[NSMutableArray alloc] init];
    [items addObject:space];
    if (numberOfPhotos > 1) [items addObject:_previousButton];
    [items addObject:space];
    if (numberOfPhotos > 1) [items addObject:_nextButton];
    [items addObject:space];
    [_toolbar setItems:items];
    [items release];
    [space release];
	[self updateNavigation];
    
    // Done button - if we're first on a nav stack
    if ([self.navigationController.viewControllers objectAtIndex:0] == self) {        
        UIBarButtonItem *doneButton = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneButtonPressed:)] autorelease];
        if ([doneButton respondsToSelector:@selector(setTintColor:)])
            doneButton.tintColor = [UIColor blackColor];
        self.navigationItem.rightBarButtonItem = doneButton;
    }
    
    // Content offset
	_pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:_currentPageIndex];
    [self tilePages];
    _performingLayout = NO;
    
}

// Release any retained subviews of the main view.
- (void)viewDidUnload {
	_currentPageIndex = 0;
    [_pagingScrollView release], _pagingScrollView = nil;
    [_visiblePages release], _visiblePages = nil;
    [_recycledPages release], _recycledPages = nil;
    [_toolbar release], _toolbar = nil;
    [_previousButton release], _previousButton = nil;
    [_nextButton release], _nextButton = nil;
    [super viewDidUnload];
}

#pragma mark - Appearance

- (void)viewWillAppear:(BOOL)animated {
    
	// Super
	[super viewWillAppear:animated];
	
	// Layout manually (iOS < 5)
    if (SYSTEM_VERSION_LESS_THAN(@"5")) [self viewWillLayoutSubviews];
    
    // Status bar appearance
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        _previousStatusBarStyle = [[UIApplication sharedApplication] statusBarStyle];
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent animated:animated];
    }
    
    // Navigation bar appearance
    self.previousNavBarTintColor = self.navigationController.navigationBar.tintColor;
    self.navigationController.navigationBar.tintColor = nil;
    _previousNavBarStyle = self.navigationController.navigationBar.barStyle;
    self.navigationController.navigationBar.barStyle = UIBarStyleBlackTranslucent;
    if ([[UINavigationBar class] respondsToSelector:@selector(appearance)]) {
        self.navigationBarBackgroundImageDefault = [self.navigationController.navigationBar backgroundImageForBarMetrics:UIBarMetricsDefault];
        self.navigationBarBackgroundImageLandscapePhone = [self.navigationController.navigationBar backgroundImageForBarMetrics:UIBarMetricsLandscapePhone];
        [self.navigationController.navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
        [self.navigationController.navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsLandscapePhone];
    }
    
    // Update UI
	[self hideControlsAfterDelay];
	
}

- (void)viewWillDisappear:(BOOL)animated {
    
	// Controls
    _viewIsVisible = NO;
    _disappearing = YES;
    [self.navigationController.navigationBar.layer removeAllAnimations]; // Stop all animations on nav bar
	[NSObject cancelPreviousPerformRequestsWithTarget:self]; // Cancel any pending toggles from taps
    [self setControlsHidden:NO animated:NO];
    
    // Status bar appearance
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
        [[UIApplication sharedApplication] setStatusBarStyle:_previousStatusBarStyle animated:animated];
    }
    
    // Reset navigation bar appearance
    // Only if we're not the root of our own nav controller
    if ([self.navigationController.viewControllers objectAtIndex:0] != self) {
        self.navigationController.navigationBar.tintColor = _previousNavBarTintColor;
        self.navigationController.navigationBar.barStyle = _previousNavBarStyle;
        if ([[UINavigationBar class] respondsToSelector:@selector(appearance)]) {
            [self.navigationController.navigationBar setBackgroundImage:_navigationBarBackgroundImageDefault forBarMetrics:UIBarMetricsDefault];
            [self.navigationController.navigationBar setBackgroundImage:_navigationBarBackgroundImageLandscapePhone forBarMetrics:UIBarMetricsLandscapePhone];
        }
    }

	// Super
	[super viewWillDisappear:animated];

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _viewIsVisible = YES;
}

#pragma mark - Layout

- (void)viewWillLayoutSubviews {
    
    // Super
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"5")) [super viewWillLayoutSubviews];
	
	// Flag
	_performingLayout = YES;
	
	// Toolbar
	_toolbar.frame = [self frameForToolbarAtOrientation:self.interfaceOrientation];
	
	// Remember index
	NSUInteger indexPriorToLayout = _currentPageIndex;
	
	// Get paging scroll view frame to determine if anything needs changing
	CGRect pagingScrollViewFrame = [self frameForPagingScrollView];
    
	// Frame needs changing
	_pagingScrollView.frame = pagingScrollViewFrame;
	
	// Recalculate contentSize based on current orientation
	_pagingScrollView.contentSize = [self contentSizeForPagingScrollView];
	
	// Adjust frames and configuration of each visible page
	for (MWZoomingScrollView *page in _visiblePages) {
        NSUInteger index = PAGE_INDEX(page);
		page.frame = [self frameForPageAtIndex:index];
        page.captionView.frame = [self frameForCaptionView:page.captionView atIndex:index];
		[page setMaxMinZoomScalesForCurrentBounds];
	}
	
	// Adjust contentOffset to preserve page location based on values collected prior to location
	_pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:indexPriorToLayout];
	[self didStartViewingPageAtIndex:_currentPageIndex]; // initial
    
	// Reset
	_currentPageIndex = indexPriorToLayout;
	_performingLayout = NO;
    
}

#pragma mark - Rotation

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation {
    return YES;
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    
	// Remember page index before rotation
	_pageIndexBeforeRotation = _currentPageIndex;
	_rotating = YES;
	
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
	
	// Perform layout
	_currentPageIndex = _pageIndexBeforeRotation;
    
	// Layout manually (iOS < 5)
    if (SYSTEM_VERSION_LESS_THAN(@"5")) [self viewWillLayoutSubviews];
	
	// Delay control holding
	[self hideControlsAfterDelay];
	
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
	_rotating = NO;
}

#pragma mark - Data

- (void)reloadData {
    
    // Reset
    _currentPageIndex = 0;
    _photoCount = NSNotFound;
    
    // Get data
    NSUInteger numberOfPhotos = [self numberOfPhotos];
    [self releaseAllUnderlyingPhotos];
    [_photos removeAllObjects];
    for (int i = 0; i < numberOfPhotos; i++) [_photos addObject:[NSNull null]];
    
    // Update
    [self performLayout];

    // Layout
    if (SYSTEM_VERSION_LESS_THAN(@"5")) [self viewWillLayoutSubviews];
    else [self.view setNeedsLayout];
    
}

- (NSUInteger)numberOfPhotos {
    if (_photoCount == NSNotFound) {
        if ([_delegate respondsToSelector:@selector(numberOfPhotosInPhotoBrowser:)]) {
            _photoCount = [_delegate numberOfPhotosInPhotoBrowser:self];
        } else if (_depreciatedPhotoData) {
            _photoCount = _depreciatedPhotoData.count;
        }
    }
    if (_photoCount == NSNotFound) _photoCount = 0;
    return _photoCount;
}

- (MWPhoto *)photoAtIndex:(NSUInteger)index {
    MWPhoto *photo = nil;
    if (index < _photos.count) {
        if ([_photos objectAtIndex:index] == [NSNull null]) {
            if ([_delegate respondsToSelector:@selector(photoBrowser:photoAtIndex:)]) {
                photo = [_delegate photoBrowser:self photoAtIndex:index];
            } else if (_depreciatedPhotoData && index < _depreciatedPhotoData.count) {
                photo = [_depreciatedPhotoData objectAtIndex:index];
            }
            if (photo) [_photos replaceObjectAtIndex:index withObject:photo];
        } else {
            photo = [_photos objectAtIndex:index];
        }
    }
    return photo;
}

- (MWCaptionView *)captionViewForPhotoAtIndex:(NSUInteger)index {
    MWCaptionView *captionView = nil;
    if ([_delegate respondsToSelector:@selector(photoBrowser:captionViewForPhotoAtIndex:)]) {
        captionView = [_delegate photoBrowser:self captionViewForPhotoAtIndex:index];
    } else {
        MWPhoto *photo = [self photoAtIndex:index];
        if (photo.caption) captionView = [[[MWCaptionView alloc] initWithPhoto:photo] autorelease];
    }
    captionView.alpha = [self areControlsHidden] ? 0 : 1; // Initial alpha
    return captionView;
}

- (UIImage *)imageForPhoto:(MWPhoto *)photo {
	if (photo) {
		// Get image or obtain in background
		if ([photo isImageAvailable]) {
			return [photo image];
		} else {
            [photo loadImageAndNotify:self];
		}
	}
	return nil;
}

- (void)loadAdjacentPhotosIfNecessary:(MWPhoto *)photo {
    MWZoomingScrollView *page = [self pageDisplayingPhoto:photo];
    if (page) {
        // If page is current page then initiate loading of previous and next pages
        NSUInteger pageIndex = PAGE_INDEX(page);
        if (_currentPageIndex == pageIndex) {
            if (pageIndex > 0) {
                // Preload index - 1
                MWPhoto *photo = [self photoAtIndex:pageIndex-1];
                if (![photo isImageAvailable]) {
                    [photo loadImageAndNotify:self];
                    MWLog(@"Pre-loading image at index %i", pageIndex-1);
                }
            }
            if (pageIndex < [self numberOfPhotos] - 1) {
                // Preload index + 1
                MWPhoto *photo = [self photoAtIndex:pageIndex+1];
                if (![photo isImageAvailable]) {
                    [photo loadImageAndNotify:self];
                    MWLog(@"Pre-loading image at index %i", pageIndex+1);
                }
            }
        }
    }
}

#pragma mark - MWPhotoDelegate

- (void)photoDidFinishLoading:(MWPhoto *)photo {
    if (photo) {
        MWZoomingScrollView *page = [self pageDisplayingPhoto:photo];
        if (page) {
            [page displayImage];
            if (_loadAdjacentWhenCurrentPhotoHasLoaded) {
                [self loadAdjacentPhotosIfNecessary:photo];
                _loadAdjacentWhenCurrentPhotoHasLoaded = NO;
            }
        }
    }
}

- (void)photoDidFailToLoad:(MWPhoto *)photo {
    _loadAdjacentWhenCurrentPhotoHasLoaded = NO;
    if (photo) {
        MWZoomingScrollView *page = [self pageDisplayingPhoto:photo];
        if (page) [page displayImageFailure];
    }
}

#pragma mark - Paging

- (void)tilePages {
	
	// Calculate which pages should be visible
	// Ignore padding as paging bounces encroach on that
	// and lead to false page loads
	CGRect visibleBounds = _pagingScrollView.bounds;
	int iFirstIndex = (int)floorf((CGRectGetMinX(visibleBounds)+PADDING*2) / CGRectGetWidth(visibleBounds));
	int iLastIndex  = (int)floorf((CGRectGetMaxX(visibleBounds)-PADDING*2-1) / CGRectGetWidth(visibleBounds));
    if (iFirstIndex < 0) iFirstIndex = 0;
    if (iFirstIndex > [self numberOfPhotos] - 1) iFirstIndex = [self numberOfPhotos] - 1;
    if (iLastIndex < 0) iLastIndex = 0;
    if (iLastIndex > [self numberOfPhotos] - 1) iLastIndex = [self numberOfPhotos] - 1;
	
	// Recycle no longer needed pages
    NSInteger pageIndex;
	for (MWZoomingScrollView *page in _visiblePages) {
        pageIndex = PAGE_INDEX(page);
		if (pageIndex < (NSUInteger)iFirstIndex || pageIndex > (NSUInteger)iLastIndex) {
			[_recycledPages addObject:page];
            [page prepareForReuse];
			[page removeFromSuperview];
			MWLog(@"Removed page at index %i", PAGE_INDEX(page));
		}
	}
	[_visiblePages minusSet:_recycledPages];
    while (_recycledPages.count > 2) // Only keep 2 recycled pages
        [_recycledPages removeObject:[_recycledPages anyObject]];
	
	// Add missing pages
	for (NSUInteger index = (NSUInteger)iFirstIndex; index <= (NSUInteger)iLastIndex; index++) {
		if (![self isDisplayingPageForIndex:index]) {
            
            // Add new page
			MWZoomingScrollView *page = [self dequeueRecycledPage];
			if (!page) {
				page = [[[MWZoomingScrollView alloc] initWithPhotoBrowser:self] autorelease];
			}
			[self configurePage:page forIndex:index];
			[_visiblePages addObject:page];
			[_pagingScrollView addSubview:page];
			MWLog(@"Added page at index %i", index);
            
            // Add caption
            MWCaptionView *captionView = [self captionViewForPhotoAtIndex:index];
            captionView.frame = [self frameForCaptionView:captionView atIndex:index];
            [_pagingScrollView addSubview:captionView];
            page.captionView = captionView;

		}
	}
	
}

- (BOOL)isDisplayingPageForIndex:(NSUInteger)index {
	for (MWZoomingScrollView *page in _visiblePages)
		if (PAGE_INDEX(page) == index) return YES;
	return NO;
}

- (MWZoomingScrollView *)pageDisplayedAtIndex:(NSUInteger)index {
	MWZoomingScrollView *thePage = nil;
	for (MWZoomingScrollView *page in _visiblePages) {
		if (PAGE_INDEX(page) == index) {
			thePage = page; break;
		}
	}
	return thePage;
}

- (MWZoomingScrollView *)pageDisplayingPhoto:(MWPhoto *)photo {
	MWZoomingScrollView *thePage = nil;
	for (MWZoomingScrollView *page in _visiblePages) {
		if (page.photo == photo) {
			thePage = page; break;
		}
	}
	return thePage;
}

- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index {
	page.frame = [self frameForPageAtIndex:index];
    page.tag = PAGE_INDEX_TAG_OFFSET + index;
    page.photo = [self photoAtIndex:index];
}

- (MWZoomingScrollView *)dequeueRecycledPage {
	MWZoomingScrollView *page = [_recycledPages anyObject];
	if (page) {
		[[page retain] autorelease];
		[_recycledPages removeObject:page];
	}
	return page;
}

// Handle page changes
- (void)didStartViewingPageAtIndex:(NSUInteger)index {
    
    // Release images further away than +/-1
    NSUInteger i;
    if (index > 0) {
        // Release anything < index - 1
        for (i = 0; i < index-1; i++) { 
            id photo = [_photos objectAtIndex:i];
            if (photo != [NSNull null]) {
                [photo releasePhoto];
                [_photos replaceObjectAtIndex:i withObject:[NSNull null]];
                MWLog(@"Released underlying image at index %i", i);
            }
        }
    }
    if (index < [self numberOfPhotos] - 1) {
        // Release anything > index + 1
        for (i = index + 2; i < _photos.count; i++) {
            id photo = [_photos objectAtIndex:i];
            if (photo != [NSNull null]) {
                [photo releasePhoto];
                [_photos replaceObjectAtIndex:i withObject:[NSNull null]];
                MWLog(@"Released underlying image at index %i", i);
            }
        }
    }
    
    // Load adjacent images if needed
    _loadAdjacentWhenCurrentPhotoHasLoaded = NO;
    MWPhoto *currentPhoto = [self photoAtIndex:index];
    if ([currentPhoto isImageAvailable]) {
        // photo loaded so load ajacent now
        [self loadAdjacentPhotosIfNecessary:currentPhoto];
    } else {
        // Photo not loaded so load adjacent when it is
        _loadAdjacentWhenCurrentPhotoHasLoaded = YES;
    }
    
}

#pragma mark - Frame Calculations

- (CGRect)frameForPagingScrollView {
    CGRect frame = self.view.bounds;// [[UIScreen mainScreen] bounds];
    frame.origin.x -= PADDING;
    frame.size.width += (2 * PADDING);
    return frame;
}

- (CGRect)frameForPageAtIndex:(NSUInteger)index {
    // We have to use our paging scroll view's bounds, not frame, to calculate the page placement. When the device is in
    // landscape orientation, the frame will still be in portrait because the pagingScrollView is the root view controller's
    // view, so its frame is in window coordinate space, which is never rotated. Its bounds, however, will be in landscape
    // because it has a rotation transform applied.
    CGRect bounds = _pagingScrollView.bounds;
    CGRect pageFrame = bounds;
    pageFrame.size.width -= (2 * PADDING);
    pageFrame.origin.x = (bounds.size.width * index) + PADDING;
    return pageFrame;
}

- (CGSize)contentSizeForPagingScrollView {
    // We have to use the paging scroll view's bounds to calculate the contentSize, for the same reason outlined above.
    CGRect bounds = _pagingScrollView.bounds;
    return CGSizeMake(bounds.size.width * [self numberOfPhotos], bounds.size.height);
}

- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index {
	CGFloat pageWidth = _pagingScrollView.bounds.size.width;
	CGFloat newOffset = index * pageWidth;
	return CGPointMake(newOffset, 0);
}

- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation {
    CGFloat height = 44;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone &&
        UIInterfaceOrientationIsLandscape(orientation)) height = 32;
	return CGRectMake(0, self.view.bounds.size.height - height, self.view.bounds.size.width, height);
}

- (CGRect)frameForCaptionView:(MWCaptionView *)captionView atIndex:(NSUInteger)index {
    CGRect pageFrame = [self frameForPageAtIndex:index];
    captionView.frame = CGRectMake(0, 0, pageFrame.size.width, 44); // set initial frame
    CGSize captionSize = [captionView sizeThatFits:CGSizeMake(pageFrame.size.width, 0)];
    CGRect captionFrame = CGRectMake(pageFrame.origin.x, pageFrame.size.height - captionSize.height - (_toolbar.superview?_toolbar.frame.size.height:0), pageFrame.size.width, captionSize.height);
    return captionFrame;
}

#pragma mark - UIScrollView Delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	
    // Checks
	if (!_viewIsVisible || _performingLayout || _rotating) return;
	
	// Tile pages
	[self tilePages];
	
	// Calculate current page
	CGRect visibleBounds = _pagingScrollView.bounds;
	int index = (int)(floorf(CGRectGetMidX(visibleBounds) / CGRectGetWidth(visibleBounds)));
    if (index < 0) index = 0;
	if (index > [self numberOfPhotos] - 1) index = [self numberOfPhotos] - 1;
	NSUInteger previousCurrentPage = _currentPageIndex;
	_currentPageIndex = index;
	if (_currentPageIndex != previousCurrentPage) {
        [self didStartViewingPageAtIndex:index];
    }
	
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	// Hide controls when dragging begins
	[self setControlsHidden:YES animated:YES];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
	// Update nav when page changes
	[self updateNavigation];
}

#pragma mark - Navigation

- (void)updateNavigation {
    
	// Title
	if ([self numberOfPhotos] > 1) {
		self.title = [NSString stringWithFormat:@"%i of %i", _currentPageIndex+1, [self numberOfPhotos]];		
	} else {
		self.title = nil;
	}
	
	// Buttons
	_previousButton.enabled = (_currentPageIndex > 0);
	_nextButton.enabled = (_currentPageIndex < [self numberOfPhotos]-1);
	
}

- (void)jumpToPageAtIndex:(NSUInteger)index {
	
	// Change page
	if (index < [self numberOfPhotos]) {
		CGRect pageFrame = [self frameForPageAtIndex:index];
		_pagingScrollView.contentOffset = CGPointMake(pageFrame.origin.x - PADDING, 0);
		[self updateNavigation];
	}
	
	// Update timer to give more time
	[self hideControlsAfterDelay];
	
}

- (void)gotoPreviousPage { [self jumpToPageAtIndex:_currentPageIndex-1]; }
- (void)gotoNextPage { [self jumpToPageAtIndex:_currentPageIndex+1]; }

#pragma mark - Control Hiding / Showing

- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated {
    
    // Cancel any timers
    [self cancelControlHiding];
	
	// Get status bar height if visible
	CGFloat statusBarHeight = 0;
	if (![UIApplication sharedApplication].statusBarHidden) {
		CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
		statusBarHeight = MIN(statusBarFrame.size.height, statusBarFrame.size.width);
	}
	
	// Status Bar
	if ([UIApplication instancesRespondToSelector:@selector(setStatusBarHidden:withAnimation:)]) {
		[[UIApplication sharedApplication] setStatusBarHidden:hidden withAnimation:animated?UIStatusBarAnimationFade:UIStatusBarAnimationNone];
	} else {
		[[UIApplication sharedApplication] setStatusBarHidden:hidden animated:animated];
	}
	
	// Get status bar height if visible
	if (![UIApplication sharedApplication].statusBarHidden) {
		CGRect statusBarFrame = [[UIApplication sharedApplication] statusBarFrame];
		statusBarHeight = MIN(statusBarFrame.size.height, statusBarFrame.size.width);
	}
	
	// Set navigation bar frame
	CGRect navBarFrame = self.navigationController.navigationBar.frame;
	navBarFrame.origin.y = statusBarHeight;
	self.navigationController.navigationBar.frame = navBarFrame;
    
    // Captions
    NSMutableSet *captionViews = [[[NSMutableSet alloc] initWithCapacity:_visiblePages.count] autorelease];
    for (MWZoomingScrollView *page in _visiblePages) {
        if (page.captionView) [captionViews addObject:page.captionView];
    }
	
	// Animate
    if (animated) {
        [UIView beginAnimations:nil context:nil];
        [UIView setAnimationDuration:0.35];
    }
    CGFloat alpha = hidden ? 0 : 1;
	[self.navigationController.navigationBar setAlpha:alpha];
	[_toolbar setAlpha:alpha];
    for (UIView *v in captionViews) v.alpha = alpha;
	if (animated) [UIView commitAnimations];
	
	// Control hiding timer
	// Will cancel existing timer but only begin hiding if
	// they are visible
	[self hideControlsAfterDelay];
	
}

- (void)cancelControlHiding {
	// If a timer exists then cancel and release
	if (_controlVisibilityTimer) {
		[_controlVisibilityTimer invalidate];
		[_controlVisibilityTimer release];
		_controlVisibilityTimer = nil;
	}
}

// Enable/disable control visiblity timer
- (void)hideControlsAfterDelay {
	if (!_disappearing && ![self areControlsHidden]) {
        [self cancelControlHiding];
		_controlVisibilityTimer = [[NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(hideControls) userInfo:nil repeats:NO] retain];
	}
}

- (BOOL)areControlsHidden { return [UIApplication sharedApplication].isStatusBarHidden; }
- (void)hideControls { [self setControlsHidden:YES animated:YES]; }
- (void)toggleControls { [self setControlsHidden:![self areControlsHidden] animated:YES]; }

#pragma mark - Properties

- (void)setInitialPageIndex:(NSUInteger)index {
    // Validate
    if (index >= [self numberOfPhotos]) index = [self numberOfPhotos]-1;
    _currentPageIndex = index;
	if ([self isViewLoaded]) {
        [self jumpToPageAtIndex:index];
        if (!_viewIsVisible) [self tilePages]; // Force tiling if view is not visible
    }
}

#pragma mark - Misc

- (void)doneButtonPressed:(id)sender {
    [self dismissModalViewControllerAnimated:YES];
}

@end