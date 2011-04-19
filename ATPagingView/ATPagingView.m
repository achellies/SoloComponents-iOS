//
//  Copyright 2011 Andrey Tarantsov. Distributed under the MIT license.
//

#import "ATPagingView.h"


@interface ATPagingView () <UIScrollViewDelegate>

- (void)configurePages;
- (void)configurePage:(UIView *)page forIndex:(NSInteger)index;

- (CGRect)frameForScrollView;
- (CGRect)frameForPageAtIndex:(NSUInteger)index;

- (void)recyclePage:(UIView *)page;

- (void)knownToBeMoving;
- (void)knownToBeIdle;

@end



@implementation ATPagingView

@synthesize delegate=_delegate;
@synthesize gapBetweenPages=_gapBetweenPages;
@synthesize pagesToPreload=_pagesToPreload;
@synthesize pageCount=_pageCount;
@synthesize currentPageIndex=_currentPageIndex;
@synthesize moving=_scrollViewIsMoving;


#pragma mark -
#pragma mark init/dealloc

- (void)commonInit {
    _visiblePages = [[NSMutableSet alloc] init];
    _recycledPages = [[NSMutableSet alloc] init];
    _currentPageIndex = 0;
    _gapBetweenPages = 20.0;
    _pagesToPreload = 1;

    // We are using an oversized UIScrollView to implement interpage gaps,
    // and we need it to clipped on the sides. This is important when
    // someone uses ATPagingView in a non-fullscreen layout.
    self.clipsToBounds = YES;

    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.pagingEnabled = YES;
    _scrollView.backgroundColor = [UIColor blackColor];
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.showsHorizontalScrollIndicator = NO;
    _scrollView.bounces = YES;
    _scrollView.delegate = self;
    [self addSubview:_scrollView];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        [self commonInit];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self commonInit];
    }
    return self;
}

- (void)dealloc {
    [_scrollView release], _scrollView = nil;
    [super dealloc];
}


#pragma mark Properties

- (void)setGapBetweenPages:(CGFloat)value {
    _gapBetweenPages = value;
    [self setNeedsLayout];
}

- (void)setPagesToPreload:(NSInteger)value {
    _pagesToPreload = value;
    [self configurePages];
}


#pragma mark -
#pragma mark Data

- (void)reloadData {
    _pageCount = [_delegate numberOfPagesInPagingView:self];

    // recycle all pages
    for (UIView *view in _visiblePages) {
        [_recycledPages addObject:view];
        [view removeFromSuperview];
    }
    [_visiblePages removeAllObjects];

    [self configurePages];
}


#pragma mark -
#pragma mark Page Views

- (UIView *)viewForPageAtIndex:(NSUInteger)index {
    for (UIView *page in _visiblePages)
        if (page.tag == index)
            return page;
    return nil;
}

- (void)configurePages {
    if (_scrollView.frame.size.width == 0)
        return;  // not our time yet

    // normally layoutSubviews won't even call us, but protect against any other calls too (e.g. if someones does reloadPages)
    if (_rotationInProgress)
        return;

    // to avoid hiccups while scrolling, do not preload invisible pages temporarily
    BOOL quickMode = (_scrollViewIsMoving && _pagesToPreload > 0);

    CGSize contentSize = CGSizeMake(_scrollView.frame.size.width * _pageCount, _scrollView.frame.size.height);
    if (!CGSizeEqualToSize(_scrollView.contentSize, contentSize)) {
        _scrollView.contentSize = contentSize;
    }

    CGRect visibleBounds = _scrollView.bounds;
    NSInteger newPageIndex = MIN(MAX(floorf(CGRectGetMidX(visibleBounds) / CGRectGetWidth(visibleBounds)), 0), _pageCount - 1);

    // calculate which pages are visible
    int firstVisiblePage = self.firstVisiblePageIndex;
    int lastVisiblePage  = self.lastVisiblePageIndex;
    int firstPage = MAX(0,            MIN(firstVisiblePage, newPageIndex - _pagesToPreload));
    int lastPage  = MIN(_pageCount-1, MAX(lastVisiblePage,  newPageIndex + _pagesToPreload));

    // recycle no longer visible pages
    for (UIView *page in _visiblePages) {
        if (page.tag < firstPage || page.tag > lastPage) {
            [self recyclePage:page];
        }
    }
    [_visiblePages minusSet:_recycledPages];

    // add missing pages
    for (int index = firstPage; index <= lastPage; index++) {
        if ([self viewForPageAtIndex:index] == nil) {
            // only preload visible pages in quick mode
            if (quickMode && (index < firstVisiblePage || index > lastVisiblePage))
                continue;
            UIView *page = [_delegate viewForPageInPagingView:self atIndex:index];
            [self configurePage:page forIndex:index];
            [_scrollView addSubview:page];
            [_visiblePages addObject:page];
        }
    }

    // update loaded pages info
    BOOL loadedPagesChanged;
    if (quickMode) {
        // Delay the notification until we actually load all the promised pages.
        // Also don't update _firstLoadedPageIndex and _lastLoadedPageIndex, so
        // that the next time we are called with quickMode==NO, we know that a
        // notification is still needed.
        loadedPagesChanged = NO;
    } else {
        loadedPagesChanged = (_firstLoadedPageIndex != firstPage || _lastLoadedPageIndex != lastPage);
        if (loadedPagesChanged) {
            _firstLoadedPageIndex = firstPage;
            _lastLoadedPageIndex  = lastPage;
            NSLog(@"loadedPagesChanged: first == %d, last == %d", _firstLoadedPageIndex, _lastLoadedPageIndex);
        }
    }

    // update current page index
    BOOL pageIndexChanged = (newPageIndex != _currentPageIndex);
    if (pageIndexChanged) {
        _currentPageIndex = newPageIndex;
        if ([_delegate respondsToSelector:@selector(currentPageDidChangeInPagingView:)])
            [_delegate currentPageDidChangeInPagingView:self];
        NSLog(@"_currentPageIndex == %d", _currentPageIndex);
    }

    if (loadedPagesChanged || pageIndexChanged) {
        if ([_delegate respondsToSelector:@selector(pagesDidChangeInPagingView:)]) {
            NSLog(@"pagesDidChangeInPagingView");
            [_delegate pagesDidChangeInPagingView:self];
        }
    }
}

- (void)configurePage:(UIView *)page forIndex:(NSInteger)index {
    page.tag = index;
    page.frame = [self frameForPageAtIndex:index];
    [page setNeedsDisplay]; // just in case
}


#pragma mark -
#pragma mark Rotation

// Why do we even have to handle rotation separately, instead of just sticking
// more magic inside layoutSubviews?
//
// This is how I've been doing rotatable paged screens since long ago.
// However, since layoutSubviews is more or less an equivalent of
// willAnimateRotation, and since there is probably a way to catch didRotate,
// maybe we can get rid of this special case.
//
// Just needs more work.

- (void)willAnimateRotation {
    _rotationInProgress = YES;

    // recycle non-current pages, otherwise they might show up during the rotation
    for (UIView *view in _visiblePages)
        if (view.tag != _currentPageIndex) {
            [self recyclePage:view];
        }
    [_visiblePages minusSet:_recycledPages];

    // We're inside an animation block, this has two consequences:
    //
    // 1) we need to resize the page view now (so that the size change is animated);
    //
    // 2) we cannot update the scroll view's contentOffset to align it with the new
    // page boundaries (since any such change will be animated in very funny ways).
    //
    // (Note that the scroll view has already been resized by now.)
    //
    // So we set the new size, but keep the old position here.
    CGSize pageSize = _scrollView.frame.size;
    [self viewForPageAtIndex:_currentPageIndex].frame = CGRectMake(_scrollView.contentOffset.x, 0, pageSize.width - _gapBetweenPages, pageSize.height);
}

- (void)didRotate {
    // Adjust frames according to the new page size - this does not cause any visible
    // changes, because we move the pages and adjust contentOffset simultaneously.
    for (UIView *view in _visiblePages)
        [self configurePage:view forIndex:view.tag];
    _scrollView.contentOffset = CGPointMake(_currentPageIndex * _scrollView.frame.size.width, 0);

    _rotationInProgress = NO;

    [self configurePages];
}


#pragma mark -
#pragma mark Layouting

- (void)layoutSubviews {
    if (_rotationInProgress)
        return;

    CGRect oldFrame = _scrollView.frame;
    CGRect newFrame = [self frameForScrollView];
    if (!CGRectEqualToRect(oldFrame, newFrame)) {
        // Strangely enough, if we do this assignment every time without the above
        // check, bouncing will behave incorrectly.
        _scrollView.frame = newFrame;
    }

    if (oldFrame.size.width != 0 && _scrollView.frame.size.width != oldFrame.size.width) {
        // rotation is in progress, don't do any adjustments just yet
    } else if (oldFrame.size.height != _scrollView.frame.size.height) {
        // some other height change (the initial change from 0 to some specific size,
        // or maybe an in-call status bar has appeared or disappeared)
        [self configurePages];
    }
}

- (NSInteger)firstVisiblePageIndex {
    CGRect visibleBounds = _scrollView.bounds;
    return MAX(floorf(CGRectGetMinX(visibleBounds) / CGRectGetWidth(visibleBounds)), 0);
}

- (NSInteger)lastVisiblePageIndex {
    CGRect visibleBounds = _scrollView.bounds;
    return MIN(floorf((CGRectGetMaxX(visibleBounds)-1) / CGRectGetWidth(visibleBounds)), _pageCount - 1);
}

- (NSInteger)firstLoadedPageIndex {
    return _firstLoadedPageIndex;
}

- (NSInteger)lastLoadedPageIndex {
    return _lastLoadedPageIndex;
}

- (CGRect)frameForScrollView {
    CGSize size = self.bounds.size;
    return CGRectMake(-_gapBetweenPages/2, 0, size.width + _gapBetweenPages, size.height);
}

// not public because this is in scroll view coordinates
- (CGRect)frameForPageAtIndex:(NSUInteger)index {
    CGFloat pageWidthWithGap = _scrollView.frame.size.width;
    CGSize pageSize = self.bounds.size;

    return CGRectMake(pageWidthWithGap * index + _gapBetweenPages/2,
                      0, pageSize.width, pageSize.height);
}


#pragma mark -
#pragma mark Recycling

// It's the caller's responsibility to remove this page from _visiblePages,
// since this method is often called while traversing _visiblePages array.
- (void)recyclePage:(UIView *)page {
    if ([page respondsToSelector:@selector(prepareForReuse)]) {
        [(id)page prepareForReuse];
    }
    [_recycledPages addObject:page];
    [page removeFromSuperview];
}

- (UIView *)dequeueReusablePage {
    UIView *result = [_recycledPages anyObject];
    if (result) {
        [_recycledPages removeObject:[[result retain] autorelease]];
    }
    return result;
}


#pragma mark -
#pragma mark UIScrollViewDelegate methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_rotationInProgress)
        return;
    [self configurePages];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [self knownToBeMoving];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) {
        [self knownToBeIdle];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self knownToBeIdle];
}


#pragma mark -
#pragma mark Busy/Idle tracking

- (void)knownToBeMoving {
    if (!_scrollViewIsMoving) {
        _scrollViewIsMoving = YES;
        if ([_delegate respondsToSelector:@selector(pagingViewWillBeginMoving:)]) {
            [_delegate pagingViewWillBeginMoving:self];
        }
    }
}

- (void)knownToBeIdle {
    if (_scrollViewIsMoving) {
        _scrollViewIsMoving = NO;

        if (_pagesToPreload > 0) {
            // we didn't preload invisible pages during scrolling, so now is the time
            [self configurePages];
        }

        if ([_delegate respondsToSelector:@selector(pagingViewDidEndMoving:)]) {
            [_delegate pagingViewDidEndMoving:self];
        }
    }
}

@end



#pragma mark -

@implementation ATPagingViewController

@synthesize pagingView=_pagingView;


#pragma mark -
#pragma mark init/dealloc

- (void)dealloc {
    [_pagingView release], _pagingView = nil;
    [super dealloc];
}


#pragma mark -
#pragma mark View Loading

- (void)loadView {
    self.view = self.pagingView = [[[ATPagingView alloc] init] autorelease];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    if (self.pagingView.delegate == nil)
        self.pagingView.delegate = self;
}


#pragma mark Lifecycle

- (void)viewWillAppear:(BOOL)animated {
    if (self.pagingView.pageCount == 0)
        [self.pagingView reloadData];
}


#pragma mark -
#pragma mark Rotation


- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [self.pagingView willAnimateRotation];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [self.pagingView didRotate];
}


#pragma mark -
#pragma mark ATPagingViewDelegate methods

- (NSInteger)numberOfPagesInPagingView:(ATPagingView *)pagingView {
    return 0;
}

- (UIView *)viewForPageInPagingView:(ATPagingView *)pagingView atIndex:(NSInteger)index {
    return nil;
}

@end
