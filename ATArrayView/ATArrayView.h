//
//  Copyright 2011 Andrey Tarantsov. Distributed under the MIT license.
//

#import <Foundation/Foundation.h>

@protocol ATArrayViewDelegate;

// A container that arranges its items in rows and columns similar to the
// thumbnails screen in Photos.app, the API is modeled after UITableView.
@interface ATArrayView : UIView {
    // subviews
    UIScrollView *_scrollView;

    // properties
    id<ATArrayViewDelegate> _delegate;

    UIEdgeInsets    _contentInsets;
    CGSize          _itemSize;
    CGFloat         _minimumColumnGap;
    CGFloat         _maximumRowGap;
    int      _preloadRowSpan;
    // state
    NSInteger       _itemCount;
    NSMutableSet   *_recycledItems;
    NSMutableSet   *_visibleItems;

    // geometry
    NSInteger       _colCount;
    NSInteger       _rowCount;
    CGFloat         _rowGap;
    CGFloat         _colGap;
    UIEdgeInsets    _effectiveInsets;
}

/* Depending on memory, I you can use the preload buffer to buffer additional rows that
should be rendered. This is useful if we are usign CATiledLayer as the layerClass of the
UIView that will be used in the grid because CATiledLayer drawRect happens in the background. Doing this will
prevent a previous reusable "grid" cell to not show the content of previous cell while we continue to render the new cell's content.
This allows for smoother scrolling and minimizing 'jerkyness' when loading network resources in cells at the tradeoff of memory.
 */
@property(nonatomic,readwrite) int preloadBuffer __attribute__ ((deprecated));
@property(nonatomic,assign) int preloadRowSpan;
@property(nonatomic, assign) IBOutlet id<ATArrayViewDelegate> delegate;

@property(nonatomic, assign) UIEdgeInsets contentInsets;

@property(nonatomic, assign) CGSize itemSize;

@property(nonatomic, assign) CGFloat minimumColumnGap;
/* Maximum row gap allows you to limit the size of the spacing between rows. If you want no spacing, set to 0, otherwise
 it will be set equal to the column gap. By default, maximumRowGap is set to INFINITY so that we always set the rowGap based on
 the column gap since it is guaranteed to be smaller than INFINITY */
@property(nonatomic, assign) CGFloat maximumRowGap;

@property(nonatomic, readonly) UIScrollView *scrollView;

@property(nonatomic, readonly) NSInteger itemCount;

@property(nonatomic, readonly) NSInteger firstVisibleItemIndex;

@property(nonatomic, readonly) NSInteger lastVisibleItemIndex;

- (void)reloadData;  // must be called at least once to display something

- (void)reloadItems; 
/* redisplayItems: same to reloadData, but also remvoes all previous "cached" item views. Useful if you change the datasource on the same grid, but need new views classes.
 */

- (UIView *)viewForItemAtIndex:(NSUInteger)index;  // nil if not loaded

- (UIView *)dequeueReusableItem;  // nil if none

- (CGRect)rectForItemAtIndex:(NSUInteger)index;

@end


@protocol ATArrayViewDelegate <NSObject>

@required

- (NSInteger)numberOfItemsInArrayView:(ATArrayView *)arrayView;

- (UIView *)viewForItemInArrayView:(ATArrayView *)arrayView atIndex:(NSInteger)index;

@end


@interface ATArrayViewController : UIViewController <ATArrayViewDelegate>

@property(nonatomic, readonly) ATArrayView *arrayView;

@end
