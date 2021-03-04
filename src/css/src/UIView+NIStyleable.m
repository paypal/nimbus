//
// Copyright 2011 Jeff Verkoeyen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "UIView+NIStyleable.h"

#import "NIDOM.h"
#import "NICSSRuleset.h"
#import "NimbusCore.h"
#import "NIUserInterfaceString.h"
#import "NIInvocationMethods.h"
#import "NIStyleable.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "Nimbus requires ARC support."
#endif

const char niView_DOMSetKey = 0;

NSString* const NICSSViewKey = @"view";
NSString* const NICSSViewIdKey = @"id";
NSString* const NICSSViewCssClassKey = @"cssClass";
NSString* const NICSSViewTextKey = @"text";
NSString* const NICSSViewTagKey = @"tag";
NSString* const NICSSViewTargetSelectorKey = @"selector";
NSString* const NICSSViewSubviewsKey = @"subviews";
NSString* const NICSSViewAccessibilityLabelKey = @"label";
NSString* const NICSSViewBackgroundColorKey = @"bg";
NSString* const NICSSViewHiddenKey = @"hidden";

const CGFloat NICSSBadValue = -1.0f;


/**
 * Private class for storing info during view creation
 */
@interface NIPrivateViewInfo : NSObject
@property (nonatomic,strong) NSMutableArray *cssClasses;
@property (nonatomic,strong) NSString *viewId;
@property (nonatomic,strong) UIView *view;
@end

///////////////////////////////////////////////////////////////////////////////////////////////////
// We split this up because we want to add all the subviews to the DOM in the order they were created
@interface UIView (NIStyleablePrivate)
-(void)_buildSubviews:(NSArray *)viewSpecs inDOM:(NIDOM *)dom withViewArray: (NSMutableArray*) subviews;
@end

NI_FIX_CATEGORY_BUG(UIView_NIStyleable)
NI_FIX_CATEGORY_BUG(UIView_NIStyleablePrivate)

CGFloat NICSSUnitToPixels(NICSSUnit unit, CGFloat container);

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@implementation UIView (NIStyleable)


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didRegisterInDOM:(NIDOM *)dom {
  NSMutableSet *set = objc_getAssociatedObject(self, &niView_DOMSetKey);
  if (!set) {
    set = NICreateNonRetainingMutableSet();
    objc_setAssociatedObject(self, &niView_DOMSetKey, set, OBJC_ASSOCIATION_RETAIN);
  }
  [set addObject:dom];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)didUnregisterInDOM:(NIDOM *)dom {
  NSMutableSet *set = objc_getAssociatedObject(self, &niView_DOMSetKey);
  [set removeObject:dom];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (NSString *)cssDescription {
  NSMutableSet *set = objc_getAssociatedObject(self, &niView_DOMSetKey);
  return [((NIDOM *)[set anyObject]) infoForView:self];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)applyViewStyleWithRuleSet:(NICSSRuleset *)ruleSet {
  [self applyViewStyleWithRuleSet:ruleSet inDOM:nil];
}
///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)applyViewStyleWithRuleSet:(NICSSRuleset *)ruleSet inDOM:(NIDOM *)dom {
  [self applyRuleSet:ruleSet inDOM:dom withViewName:nil];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)applyRuleSet: (NICSSRuleset*) ruleSet inDOM: (NIDOM*)dom withViewName: (NSString*) name {
  if ([ruleSet hasBackgroundColor]) {
    self.backgroundColor = ruleSet.backgroundColor;
  }
  if ([ruleSet hasAccessibilityTraits]) {
    self.accessibilityTraits = ruleSet.accessibilityTraits;
  }
  if ([ruleSet hasClipsToBounds]) {
    self.clipsToBounds = ruleSet.clipsToBounds;
  }
  if ([ruleSet hasOpacity]) {
    self.alpha = ruleSet.opacity;
  }
  if ([ruleSet hasBorderRadius]) {
    self.layer.cornerRadius = ruleSet.borderRadius;
  }
  if ([ruleSet hasBorderWidth]) {
    self.layer.borderWidth = ruleSet.borderWidth;
  }
  if ([ruleSet hasBorderColor]) {
    self.layer.borderColor = ruleSet.borderColor.CGColor;
  }
  if ([ruleSet hasAutoresizing]) {
    self.autoresizingMask = ruleSet.autoresizing;
  }
  if ([ruleSet hasVisible]) {
    self.hidden = !ruleSet.visible;
  }
  
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // View sizing
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Special case auto/auto height and width
  if ([ruleSet hasWidth] && [ruleSet hasHeight] &&
      ruleSet.width.type == CSS_AUTO_UNIT && ruleSet.height.type == CSS_AUTO_UNIT) {
    if ([self respondsToSelector:@selector(autoSize:inDOM:)]) {
      [((id<NIStyleable>)self) autoSize: ruleSet inDOM: dom];
    } else {
      [self sizeToFit];
    }
    if (ruleSet.hasVerticalPadding) {
      NICSSUnit vPadding = ruleSet.verticalPadding;
      switch (vPadding.type) {
        case CSS_AUTO_UNIT:
          break;
        case CSS_PERCENTAGE_UNIT:
          self.frameHeight += roundf(self.frameHeight * vPadding.value);
          break;
        case CSS_PIXEL_UNIT:
          self.frameHeight += vPadding.value;
          break;
      }
    }
    if (ruleSet.hasHorizontalPadding) {
      NICSSUnit hPadding = ruleSet.horizontalPadding;
      switch (hPadding.type) {
        case CSS_AUTO_UNIT:
          break;
        case CSS_PERCENTAGE_UNIT:
          self.frameWidth += roundf(self.frameWidth * hPadding.value);
          break;
        case CSS_PIXEL_UNIT:
          self.frameWidth += hPadding.value;
          break;
      }
    }
    
  } else {
    if ([ruleSet hasWidth]) {
      NICSSUnit u = ruleSet.width;
      CGFloat startHeight = self.frameHeight;
      switch (u.type) {
        case CSS_AUTO_UNIT:
          if ([self respondsToSelector:@selector(autoSize:inDOM:)]) {
            [((id<NIStyleable>)self) autoSize:ruleSet inDOM:dom];
          } else {
            [self sizeToFit]; // sizeToFit the width, but retain height. Behavior somewhat undefined...
            self.frameHeight = startHeight;
          }
          break;
        case CSS_PERCENTAGE_UNIT:
          self.frameWidth = roundf(self.superview.bounds.size.width * u.value);
          break;
        case CSS_PIXEL_UNIT:
          // Because padding and margin are (a) complicated to implement and (b) not relevant in a non-flow layout,
          // we use negative width values to mean "the superview dimension - the value." It's a little hokey, but
          // it's very useful. If someone wants to layer on padding primitives to deal with this in a more CSSy way,
          // go for it.
          if (u.value < 0) {
            self.frameWidth = self.superview.frameWidth + u.value;
          } else {
            self.frameWidth = u.value;
          }
          break;
      }
      if (ruleSet.hasHorizontalPadding) {
        NICSSUnit hPadding = ruleSet.horizontalPadding;
        switch (hPadding.type) {
          case CSS_AUTO_UNIT:
            break;
          case CSS_PERCENTAGE_UNIT:
            self.frameWidth += roundf(self.frameWidth * hPadding.value);
            break;
          case CSS_PIXEL_UNIT:
            self.frameWidth += hPadding.value;
            break;
        }
      }
    }
    if ([ruleSet hasHeight]) {
      NICSSUnit u = ruleSet.height;
      CGFloat startWidth = self.frameWidth;
      switch (u.type) {
        case CSS_AUTO_UNIT:
          if ([self respondsToSelector:@selector(autoSize:inDOM:)]) {
            [((id<NIStyleable>)self) autoSize:ruleSet inDOM:dom];
          } else {
            [self sizeToFit];
            self.frameWidth = startWidth;
          }
          break;
        case CSS_PERCENTAGE_UNIT:
          self.frameHeight = roundf(self.superview.bounds.size.height * u.value);
          break;
        case CSS_PIXEL_UNIT:
          // Because padding and margin are (a) complicated to implement and (b) not relevant in a non-flow layout,
          // we use negative width values to mean "the superview dimension - the value." It's a little hokey, but
          // it's very useful. If someone wants to layer on padding primitives to deal with this in a more CSSy way,
          // go for it.
          if (u.value < 0) {
            self.frameHeight = self.superview.frameHeight + u.value;
          } else {
            self.frameHeight = u.value;
          }
          break;
      }
      if (ruleSet.hasVerticalPadding) {
        NICSSUnit vPadding = ruleSet.verticalPadding;
        switch (vPadding.type) {
          case CSS_AUTO_UNIT:
            break;
          case CSS_PERCENTAGE_UNIT:
            self.frameHeight += roundf(self.frameHeight * vPadding.value);
            break;
          case CSS_PIXEL_UNIT:
            self.frameHeight += vPadding.value;
            break;
        }
      }
    }
  }
  
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Left
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasLeft]) {
    NICSSUnit u = ruleSet.left;
    switch (u.type) {
      case CSS_PERCENTAGE_UNIT:
      case CSS_PIXEL_UNIT:
        self.frameMinX = NICSSUnitToPixels(u, self.superview.frameWidth);
        break;
      default:
            NIDASSERT(u.type == CSS_PERCENTAGE_UNIT || u.type == CSS_PIXEL_UNIT);
        break;
    }
  }
  if (ruleSet.hasRightOf) {
    CGPoint anchor;
    NICSSRelativeSpec *rightOf = ruleSet.rightOf;
    UIView *relative = [self relativeViewFromViewSpec:rightOf.viewSpec inDom:dom];
    if (relative) {
      [dom ensureViewHasBeenRefreshed:relative];
      switch (rightOf.margin.type) {
        case CSS_AUTO_UNIT:
          // Align x center
          anchor = CGPointMake(relative.frameMidX, 0);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          self.frameMidX = anchor.x;
          break;
        case CSS_PERCENTAGE_UNIT:
        case CSS_PIXEL_UNIT:
          // relative.frameMinX - (relative.frameHeight * unit)
          anchor = CGPointMake(relative.frameMaxX, 0);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          self.frameMinX = anchor.x + NICSSUnitToPixels(rightOf.margin, relative.frameWidth);
          break;
      }
    }
  }
  
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Right
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasRight]) {
    NICSSUnit u = ruleSet.right;
    CGFloat newMaxX = self.superview.frameWidth - NICSSUnitToPixels(u, self.superview.frameWidth);
    switch (u.type) {
      case CSS_PERCENTAGE_UNIT:
      case CSS_PIXEL_UNIT:
        if (ruleSet.hasLeft || ruleSet.hasRightOf) {
          // If this ruleset specifies the left position of this view, then we set the right position
          // while maintaining that left position (by modifying the frame width).
          self.frameWidth = newMaxX - self.frameMinX;
          // We just modified the width of the view. The auto-height of the view might depend on its width
          // (i.e. a multi-line label), so we need to recalculate the height if it was auto.
          CGFloat startWidth = self.frameWidth;
          if (ruleSet.hasHeight && ruleSet.height.type == CSS_AUTO_UNIT) {
            if ([self respondsToSelector:@selector(autoSize:inDOM:)]) {
              [((id<NIStyleable>)self) autoSize:ruleSet inDOM:dom];
            } else {
              [self sizeToFit];
              self.frameWidth = startWidth;
            }
          }
          // ...and now we've just modified the height, so we need to re-set the vertical padding
          if (ruleSet.hasVerticalPadding) {
            NICSSUnit vPadding = ruleSet.verticalPadding;
            switch (vPadding.type) {
              case CSS_AUTO_UNIT:
                break;
              case CSS_PERCENTAGE_UNIT:
                self.frameHeight += roundf(self.frameHeight * vPadding.value);
                break;
              case CSS_PIXEL_UNIT:
                self.frameHeight += vPadding.value;
                break;
            }
          }
        } else {
          // Otherwise, just set the right position normally
          self.frameMaxX = newMaxX;
        }
        break;
      default:
        NIDASSERT(u.type == CSS_PERCENTAGE_UNIT || u.type == CSS_PIXEL_UNIT);
        break;
    }
  }
  if (ruleSet.hasLeftOf) {
    CGPoint anchor;
    NICSSRelativeSpec *leftOf = ruleSet.leftOf;
    UIView *relative = [self relativeViewFromViewSpec:leftOf.viewSpec inDom:dom];
    if (relative) {
      [dom ensureViewHasBeenRefreshed:relative];
      switch (leftOf.margin.type) {
        case CSS_AUTO_UNIT:
          // Align x center
          anchor = CGPointMake(relative.frameMidX, 0);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          self.frameMidX = anchor.x;
          break;
        case CSS_PERCENTAGE_UNIT:
        case CSS_PIXEL_UNIT:
          anchor = CGPointMake(relative.frameMinX, 0);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          if (ruleSet.hasLeft || ruleSet.hasRightOf) {
            // If this ruleset specifies the left position of this view, then we set the right position
            // while maintaining that left position (by modifying the frame width).
            self.frameWidth = anchor.x - NICSSUnitToPixels(leftOf.margin, relative.frameWidth) - self.frameMinX;
            // We just modified the width of the view. The auto-height of the view might depend on its width
            // (i.e. a multi-line label), so we need to recalculate the height if it was auto.
            CGFloat startWidth = self.frameWidth;
            if (ruleSet.hasHeight && ruleSet.height.type == CSS_AUTO_UNIT) {
              if ([self respondsToSelector:@selector(autoSize:inDOM:)]) {
                [((id<NIStyleable>)self) autoSize:ruleSet inDOM:dom];
              } else {
                [self sizeToFit];
                self.frameWidth = startWidth;
              }
            }
            // ...and now we've just modified the height, so we need to re-set the vertical padding
            if (ruleSet.hasVerticalPadding) {
              NICSSUnit vPadding = ruleSet.verticalPadding;
              switch (vPadding.type) {
                case CSS_AUTO_UNIT:
                  break;
                case CSS_PERCENTAGE_UNIT:
                  self.frameHeight += roundf(self.frameHeight * vPadding.value);
                  break;
                case CSS_PIXEL_UNIT:
                  self.frameHeight += vPadding.value;
                  break;
              }
            }
          } else {
            // Otherwise, just set the right position normally
            self.frameMaxX = anchor.x - NICSSUnitToPixels(leftOf.margin, relative.frameWidth);
          }
          break;
      }
    }
  }

  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Horizontal Min/Max
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasMinWidth]) {
    CGFloat min = NICSSBadValue;
    if (ruleSet.minWidth.type == CSS_PERCENTAGE_UNIT) {
      min = roundf(self.superview.bounds.size.width * ruleSet.minWidth.value);
    } else if (ruleSet.minWidth.type == CSS_PIXEL_UNIT) {
      min = NICSSUnitToPixels(ruleSet.minWidth,self.frameWidth);
    } else {
      NIDASSERT(NO);
    }

    if (min != NICSSBadValue && self.frameWidth < min) {
      self.frameWidth = min;
    }
  }
  if ([ruleSet hasMaxWidth]) {
    CGFloat max = NICSSBadValue;
    if (ruleSet.maxWidth.type == CSS_PERCENTAGE_UNIT) {
      max = roundf(self.superview.bounds.size.width * ruleSet.maxWidth.value);
    } else if (ruleSet.maxWidth.type == CSS_PIXEL_UNIT) {
      max = NICSSUnitToPixels(ruleSet.maxWidth,self.frameWidth);
    } else {
      NIDASSERT(NO);
    }

    if (max != NICSSBadValue && self.frameWidth > max) {
      self.frameWidth = max;
    }
  }

  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Horizontal Align
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasFrameHorizontalAlign]) {
    switch (ruleSet.frameHorizontalAlign) {
      case NSTextAlignmentCenter:
        self.frameMidX = roundf(self.superview.bounds.size.width / 2.0);
        break;
      case NSTextAlignmentLeft:
        self.frameMinX = 0;
        break;
      case NSTextAlignmentRight:
        self.frameMaxX = self.superview.bounds.size.width;
        break;
      default:
        NIDASSERT(NO);
        break;
    }
  }
  
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Top
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasTop]) {
    NICSSUnit u = ruleSet.top;
    switch (u.type) {
      case CSS_PERCENTAGE_UNIT:
      case CSS_PIXEL_UNIT:
        self.frameMinY = NICSSUnitToPixels(u, self.superview.frameHeight);
        break;
      default:
        NIDASSERT(u.type == CSS_PERCENTAGE_UNIT || u.type == CSS_PIXEL_UNIT);
        break;
    }
  }
  if (ruleSet.hasBelow) {
    CGPoint anchor;
    NICSSRelativeSpec *below = ruleSet.below;
    UIView *relative = [self relativeViewFromViewSpec:below.viewSpec inDom:dom];
    if (relative) {
      [dom ensureViewHasBeenRefreshed:relative];
      switch (below .margin.type) {
        case CSS_AUTO_UNIT:
          // Align y center
          anchor = CGPointMake(0, relative.frameMidY);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          self.frameMidY = anchor.y;
          break;
        case CSS_PERCENTAGE_UNIT:
        case CSS_PIXEL_UNIT:
          anchor = CGPointMake(0, relative.frameMaxY);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          self.frameMinY = anchor.y + NICSSUnitToPixels(below.margin, relative.frameHeight);
          break;
      }
    }
  }
  
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Bottom
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasBottom]) {
    NICSSUnit u = ruleSet.bottom;
    CGFloat newBottom = self.superview.frameHeight - NICSSUnitToPixels(u, self.superview.frameHeight);
    switch (u.type) {
      case CSS_PERCENTAGE_UNIT:
      case CSS_PIXEL_UNIT:
        if (ruleSet.hasTop || ruleSet.hasBelow) {
          // If this ruleset specifies the top position of this view, then we set the bottom position
          // while maintaining that top position (by modifying the frame height).
          self.frameHeight = newBottom - self.frameMinY;
        } else {
          // Otherwise, just set the bottom normally
          self.frameMaxY = newBottom;
        }
        break;
      default:
        NIDASSERT(u.type == CSS_PERCENTAGE_UNIT || u.type == CSS_PIXEL_UNIT);
        break;
    }
  }
  if (ruleSet.hasAbove) {
    CGPoint anchor;
    NICSSRelativeSpec *above = ruleSet.above;
    UIView *relative = [self relativeViewFromViewSpec:above.viewSpec inDom:dom];
    if (relative) {
      [dom ensureViewHasBeenRefreshed:relative];
      switch (above.margin.type) {
        case CSS_AUTO_UNIT:
          // Align y center
          anchor = CGPointMake(0, relative.frameMidY);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          self.frameMidY = anchor.y;
          break;
        case CSS_PERCENTAGE_UNIT:
        case CSS_PIXEL_UNIT:
          anchor = CGPointMake(0, relative.frameMinY);
          if (self.superview != relative.superview) {
            anchor = [self convertPoint:anchor fromView:relative.superview];
          }
          if (ruleSet.hasTop || ruleSet.hasBelow) {
            // If this ruleset specifies the top position of this view, then we set the bottom position
            // while maintaining that top position (by modifying the frame height).
            self.frameHeight = anchor.y - NICSSUnitToPixels(above.margin, relative.frameHeight) - self.frameMinY;
          } else {
            // Otherwise, just set the bottom position normally
            self.frameMaxY = anchor.y - NICSSUnitToPixels(above.margin, relative.frameHeight);
          }
          break;
      }
    }
  }

  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Vertical Min/Max
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasMinHeight]) {
    CGFloat min = NICSSBadValue;
    if (ruleSet.minHeight.type == CSS_PERCENTAGE_UNIT) {
      min = roundf(self.superview.bounds.size.height * ruleSet.minHeight.value);
    } else if (ruleSet.minHeight.type == CSS_PIXEL_UNIT) {
      min = NICSSUnitToPixels(ruleSet.minHeight,self.frameHeight);
    } else {
      NIDASSERT(NO);
    }

    if (min != NICSSBadValue && self.frameHeight < min) {
      self.frameHeight = min;
    }
  }
  if ([ruleSet hasMaxHeight]) {
    CGFloat max = NICSSBadValue;
    if (ruleSet.maxHeight.type == CSS_PERCENTAGE_UNIT) {
      max = roundf(self.superview.bounds.size.height * ruleSet.maxHeight.value);
    } else if (ruleSet.maxHeight.type == CSS_PIXEL_UNIT) {
      max = NICSSUnitToPixels(ruleSet.maxHeight,self.frameHeight);
    } else {
      NIDASSERT(NO);
    }

    if (max != NICSSBadValue && self.frameHeight > max) {
      self.frameHeight = max;
    }
  }

  ///////////////////////////////////////////////////////////////////////////////////////////////////
  // Vertical Align
  ///////////////////////////////////////////////////////////////////////////////////////////////////
  if ([ruleSet hasFrameVerticalAlign]) {
    switch (ruleSet.frameVerticalAlign) {
      case UIViewContentModeCenter:
        self.frameMidY = roundf(self.superview.bounds.size.height / 2.0);
        break;
      case UIViewContentModeTop:
        self.frameMinY = 0;
        break;
      case UIViewContentModeBottom:
        self.frameMaxY = self.superview.bounds.size.height;
        break;
      default:
        NIDASSERT(NO);
        break;
    }
  }
  



}

- (UIView *)relativeViewFromViewSpec:(NSString *)viewSpec inDom:(NIDOM *)dom
{
  UIView* relative = nil;
  if ([viewSpec characterAtIndex:0] == '\\') {
    if ([viewSpec caseInsensitiveCompare:@"\\next"] == NSOrderedSame) {
      NSInteger ix = [self.superview.subviews indexOfObject:self];
      if (++ix < self.superview.subviews.count) {
        relative = [self.superview.subviews objectAtIndex:ix];
      }
    } else if ([viewSpec caseInsensitiveCompare:@"\\prev"] == NSOrderedSame) {
      NSInteger ix = [self.superview.subviews indexOfObject:self];
      if (ix > 0) {
        relative = [self.superview.subviews objectAtIndex:ix-1];
      }
    } else if ([viewSpec caseInsensitiveCompare:@"\\first"] == NSOrderedSame) {
      relative = [self.superview.subviews objectAtIndex:0];
      if (relative == self) { relative = nil; }
    } else if ([viewSpec caseInsensitiveCompare:@"\\last"] == NSOrderedSame) {
      relative = [self.superview.subviews lastObject];
      if (relative == self) { relative = nil; }
    }
  } else {
    relative = [dom viewById:viewSpec];
  }
  return relative;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
-(NSArray *)buildSubviews:(NSArray *)viewSpecs inDOM:(NIDOM *)dom
{
  NSMutableArray *subviews = [[NSMutableArray alloc] init];
  [self _buildSubviews:viewSpecs inDOM:dom withViewArray:subviews];
  
  for (NSUInteger ix = 0, ct = subviews.count; ix < ct; ix++) {
    NIPrivateViewInfo *viewInfo = [subviews objectAtIndex:ix];
    NSString *firstClass = [viewInfo.cssClasses count] ? [viewInfo.cssClasses objectAtIndex:0] : nil;
    [dom registerView:viewInfo.view withCSSClass:firstClass andId:viewInfo.viewId];
    if (viewInfo.viewId && dom.target) {
      // This sets the property on a container corresponding to the id of a contained view
      NSString *selectorName = [NSString stringWithFormat:@"set%@%@:", [[viewInfo.viewId substringWithRange:NSMakeRange(1, 1)] uppercaseString], [viewInfo.viewId substringFromIndex:2]];
      SEL selector = NSSelectorFromString(selectorName);
      if ([dom.target respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [dom.target performSelector:selector withObject:viewInfo.view];
#pragma clang diagnostic pop
      }
    }
    if (viewInfo.cssClasses.count > 1) {
      for (NSUInteger i = 1, cct = viewInfo.cssClasses.count; i < cct; i++) {
        [dom addCssClass:[viewInfo.cssClasses objectAtIndex:i] toView:viewInfo.view];
      }
    }
    [subviews replaceObjectAtIndex:ix withObject:viewInfo.view];
  }
  return subviews;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)applyStyleWithRuleSet:(NICSSRuleset *)ruleSet inDOM:(NIDOM *)dom {
  [self applyViewStyleWithRuleSet:ruleSet inDOM:dom];
}

- (CGFloat)frameWidth
{
	return self.frame.size.width;
}

- (void)setFrameWidth:(CGFloat)frameWidth
{
	CGRect frame = self.frame;
	frame.size.width = frameWidth;
  
	self.frame = frame;
}

- (CGFloat)frameHeight
{
	return self.frame.size.height;
}

- (void)setFrameHeight:(CGFloat)frameHeight
{
	CGRect frame = self.frame;
	frame.size.height = frameHeight;
  
	self.frame = frame;
}

- (CGFloat)frameMinX
{
	return CGRectGetMinX(self.frame);
}

- (void)setFrameMinX:(CGFloat)frameMinX
{
	CGRect frame = self.frame;
	frame.origin.x = frameMinX;
  
	self.frame = frame;
}

- (CGFloat)frameMidX
{
	return CGRectGetMidX(self.frame);
}

- (void)setFrameMidX:(CGFloat)frameMidX
{
	self.frameMinX = (frameMidX - roundf(self.frameWidth / 2.0f));
}

- (CGFloat)frameMaxX
{
	return CGRectGetMaxX(self.frame);
}

- (void)setFrameMaxX:(CGFloat)frameMaxX
{
	self.frameMinX = (frameMaxX - self.frameWidth);
}

- (CGFloat)frameMinY
{
	return CGRectGetMinY(self.frame);
}

- (void)setFrameMinY:(CGFloat)frameMinY
{
	CGRect frame = self.frame;
	frame.origin.y = frameMinY;
  
	self.frame = frame;
}

- (CGFloat)frameMidY
{
	return CGRectGetMidY(self.frame);
}

- (void)setFrameMidY:(CGFloat)frameMidY
{
	self.frameMinY = (frameMidY - roundf(self.frameHeight / 2.0f));
}

- (CGFloat)frameMaxY
{
	return CGRectGetMaxY(self.frame);
}

- (void)setFrameMaxY:(CGFloat)frameMaxY
{
	self.frameMinY = (frameMaxY - self.frameHeight);
}

@end

CGFloat NICSSUnitToPixels(NICSSUnit unit, CGFloat container)
{
  if (unit.type == CSS_PERCENTAGE_UNIT) {
    CGFloat value = unit.value * container;
    // If someone has specified 100%, match the target value exactly without rounding.
    if (unit.value != 1.0f && unit.value != -1.0f) {
        value = roundf(value);
    }
    return value;
  }
  return unit.value;
}


@implementation UIView (NIStyleablePrivate)
-(void)_buildSubviews:(NSArray *)viewSpecs inDOM:(NIDOM *)dom withViewArray:(NSMutableArray *)subviews
{
    NIPrivateViewInfo *active = [[NIPrivateViewInfo alloc] init];
    active.view = self;
    [subviews addObject:active];
	for (id directive in viewSpecs) {
    
    if ([directive isKindOfClass:[NSDictionary class]]) {
      // Process the key value pairs rather than trying to determine intent
      // from the type of an array of random objects

      // We need a mutable copy so we can figure out if any custom values are left after we get ours out
      NSMutableDictionary *kv = [(NSDictionary*) directive mutableCopy];
      if (!active) {
        NSAssert([kv objectForKey:NICSSViewKey], @"The first NSDictionary passed to build subviews must contain the NICSSViewKey");
      }
      id directiveValue = [kv objectForKey:NICSSViewKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewKey];
#ifdef NI_DYNAMIC_VIEWS
        // Let's see if this is a UIView subclass. If NOT, let the normal string property handling take over
        if ([directiveValue isKindOfClass:[NSString class]]) {
          id classFromString = [[NSClassFromString(directiveValue) alloc] init];
          if (classFromString) {
            directiveValue = [[NSClassFromString(directiveValue) alloc] init];
          }
        }
        // See if we support this property and if so, pass it the dictionary itself (optionally the DOM). This allows extensions
        // of the parser for things like table rows. It's mainly in concert with the XML parser, otherwise the syntax would just be odd.
        if ([directiveValue isKindOfClass:[NSString class]]) {
          NSString *targetSelectorStr = [NSString stringWithFormat:@"set%@:inDOM:",directiveValue];
          SEL targetSelector = NSSelectorFromString(targetSelectorStr);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
          if (targetSelector && [self respondsToSelector:targetSelector])
          {
            [self performSelector:targetSelector withObject:viewSpecs withObject:dom];
            return;
          }
#pragma clang diagnostic pop
          
          targetSelectorStr = [NSString stringWithFormat:@"set%@:",directiveValue];
          targetSelector = NSSelectorFromString(targetSelectorStr);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
          if (targetSelector && [self respondsToSelector:targetSelector])
          {
            [self performSelector:targetSelector withObject:viewSpecs];
            return;
          }
#pragma clang diagnostic pop
        }
#endif
        if ([directiveValue isKindOfClass:[UIView class]]) {
          active = [[NIPrivateViewInfo alloc] init];
          active.view = (UIView*) directiveValue;
          if (self != active.view) {
            [self addSubview:active.view];
          }
          [subviews addObject: active];
        } else if (class_isMetaClass(object_getClass(directiveValue))) {
          active = [[NIPrivateViewInfo alloc] init];
          active.view = [[directive alloc] init];
          NSAssert([active.view isKindOfClass:[UIView class]], @"View must inherit from UIView. %@ does not.", NSStringFromClass([active class]));
          [self addSubview:active.view];
          [subviews addObject: active];
        } else {
          NSAssert(NO, @"NICSSViewKey directive does not identify a UIView or UIView class.");
        }
      }
      directiveValue = [kv objectForKey:NICSSViewIdKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewIdKey];
        NSAssert([directiveValue isKindOfClass:[NSString class]], @"The value of NICSSViewIdKey must be an NSString*");
        if (![directiveValue hasPrefix:@"#"]) {
          directiveValue = [@"#" stringByAppendingString:directiveValue];
        }
        active.viewId = directiveValue;
      }
      directiveValue = [kv objectForKey:NICSSViewCssClassKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewCssClassKey];
        NSAssert([directiveValue isKindOfClass:[NSString class]] || [directiveValue isKindOfClass:[NSArray class]], @"The value of NICSSViewCssClassKey must be an NSString* or NSArray*");
        active.cssClasses = active.cssClasses ?: [[NSMutableArray alloc] init];
        if ([directiveValue isKindOfClass:[NSString class]]) {
          if ([directiveValue rangeOfString:@" "].location != NSNotFound) {
            [active.cssClasses addObjectsFromArray:[directiveValue componentsSeparatedByString:@" "]];
          } else {
            [active.cssClasses addObject:directiveValue];
          }
        } else {
          [active.cssClasses addObjectsFromArray:directiveValue];
        }
      }
      directiveValue = [kv objectForKey:NICSSViewTextKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewTextKey];
        NSAssert([directiveValue isKindOfClass:[NSString class]] || [directiveValue isKindOfClass:[NIUserInterfaceString class]], @"The value of NICSSViewCssClassKey must be an NSString* or NIUserInterfaceString*");
        if ([directiveValue isKindOfClass:[NSString class]]) {
          directiveValue = [[NIUserInterfaceString alloc] initWithKey:directiveValue defaultValue:directiveValue];
        }
        if ([directiveValue isKindOfClass:[NIUserInterfaceString class]]) {
          [((NIUserInterfaceString*)directiveValue) attach:active.view];
        }
      }
      directiveValue = [kv objectForKey:NICSSViewBackgroundColorKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewBackgroundColorKey];
        NSAssert([directiveValue isKindOfClass:[UIColor class]] || [directiveValue isKindOfClass:[NSNumber class]] || [directiveValue isKindOfClass:[NSString class]], @"The value of NICSSViewBackgroundColorKey must be NSString*, NSNumber* or UIColor*");
        if ([directiveValue isKindOfClass:[NSNumber class]]) {
          long rgbValue = [directiveValue longValue];
          directiveValue = [UIColor colorWithRed:((float)((rgbValue & 0xFF000000) >> 24))/255.0 green:((float)((rgbValue & 0xFF0000) >> 16))/255.0 blue:((float)((rgbValue & 0xFF00) >> 8))/255.0 alpha:((float)(rgbValue & 0xFF))/255.0];
        } else if ([directiveValue isKindOfClass:[NSString class]]) {
          directiveValue = [NICSSRuleset colorFromString:directiveValue];
        }
        active.view.backgroundColor = directiveValue;
      }
      directiveValue = [kv objectForKey:NICSSViewHiddenKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewHiddenKey];
        NSAssert([directiveValue isKindOfClass:[NSNumber class]] || [directiveValue isKindOfClass:[NSString class]], @"The value of NICSSViewHiddenKey must be NSString* or NSNumber*");
        active.view.hidden = [directiveValue boolValue];
      }
      directiveValue = [kv objectForKey:NICSSViewTagKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewTagKey];
        NSAssert([directiveValue isKindOfClass:[NSNumber class]], @"The value of NICSSViewTagKey must be an NSNumber*");
        active.view.tag = [directiveValue integerValue];
      }
      directiveValue = [kv objectForKey:NICSSViewTargetSelectorKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewTargetSelectorKey];
        NSAssert([directiveValue isKindOfClass:[NSInvocation class]] || [directiveValue isKindOfClass:[NSString class]], @"NICSSViewTargetSelectorKey must be an NSInvocation*, or an NSString* if you're adventurous and NI_DYNAMIC_VIEWS is defined.");
        
#ifdef NI_DYNAMIC_VIEWS
        // NSSelectorFromString has Apple rejection written all over it, even though it's documented. Since its intended
        // use is primarily rapid development right now, use the #ifdef to turn it on.
        if ([directiveValue isKindOfClass:[NSString class]]) {
          // Let's make an invocation out of this puppy.
          @try {
            SEL selector = NSSelectorFromString(directiveValue);
            directiveValue = NIInvocationWithInstanceTarget(dom.target, selector);
          }
          @catch (NSException *exception) {
#ifdef DEBUG
            NIDPRINT(@"Unknown selector %@ specified on %@.", directiveValue, dom.target);
#endif
          }
        }
#endif
        
        if ([directiveValue isKindOfClass:[NSInvocation class]]) {
          NSInvocation *n = (NSInvocation*) directiveValue;
          if ([active.view respondsToSelector:@selector(addTarget:action:forControlEvents:)]) {
              if ([active.view isKindOfClass:[UIButton class]]) {
                  [((id)active.view) addTarget: n.target action: n.selector forControlEvents: UIControlEventTouchUpInside];
              } else {
                  [((id)active.view) addTarget: n.target action: n.selector forControlEvents: UIControlEventEditingChanged];
              }
          } else {
            NSString *error = [NSString stringWithFormat:@"Cannot apply NSInvocation to class %@", NSStringFromClass(active.class)];
            NSAssert(NO, error);
          }
        }
      }
      directiveValue = [kv objectForKey:NICSSViewSubviewsKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewSubviewsKey];
        NSAssert([directiveValue isKindOfClass: [NSArray class]], @"NICSSViewSubviewsKey must be an NSArray*");
        [active.view _buildSubviews:directiveValue inDOM:dom withViewArray:subviews];
      }
      
      directiveValue = [kv objectForKey:NICSSViewAccessibilityLabelKey];
      if (directiveValue) {
        [kv removeObjectForKey:NICSSViewAccessibilityLabelKey];
        NSAssert([directiveValue isKindOfClass:[NSString class]], @"NICSSViewAccessibilityLabelKey must be an NSString*");
        active.view.accessibilityLabel = directiveValue;
      }
      
      if (kv.count) {
        // The rest go to kv setters
        NISetValuesForKeys(active.view, kv, nil);
      }
      
      continue;
    }
    
    // This first element in a "segment" of the array must be a view or a class object that we will make into a view
    // You can do things like UIView.alloc.init, UIView.class, [[UIView alloc] init]...
    if ([directive isKindOfClass: [UIView class]]) {
      active = [[NIPrivateViewInfo alloc] init];
      active.view = (UIView*) directive;
      if (self != directive) {
        [self addSubview:active.view];
      }
      [subviews addObject: active];
      continue;
    } else if (class_isMetaClass(object_getClass(directive))) {
      active = [[NIPrivateViewInfo alloc] init];
      active.view = [[directive alloc] init];
      [self addSubview:active.view];
      [subviews addObject: active];
      continue;
    } else if (!active) {
      NSAssert(NO, @"UIView::buildSubviews expected UIView or Class to start a directive.");
      continue;
    }
    
    if ([directive isKindOfClass:[NIUserInterfaceString class]]) {
      [((NIUserInterfaceString*)directive) attach:active.view];
    } else if ([directive isKindOfClass:[NSString class]]) {
      // Strings are either a cssClass or an accessibility label
      NSString *d = (NSString*) directive;
      if ([d hasPrefix:@"."]) {
        active.cssClasses = active.cssClasses ?: [[NSMutableArray alloc] init];
        [active.cssClasses addObject: [d substringFromIndex:1]];
      } else if ([d hasPrefix:@"#"]) {
        active.viewId = d;
      } else {
        active.view.accessibilityLabel = d;
      }
    } else if ([directive isKindOfClass:[NSNumber class]]) {
      // NSNumber means tag
      active.view.tag = [directive integerValue];
    } else if ([directive isKindOfClass:[NSArray class]]) {
      // NSArray means recursive call to build
      [active.view _buildSubviews:directive inDOM:dom withViewArray:subviews];
    } else if ([directive isKindOfClass:[UIColor class]]) {
      active.view.backgroundColor = directive;
    } else if ([directive isKindOfClass:[NSInvocation class]]) {
      NSInvocation *n = (NSInvocation*) directive;
      if ([active.view respondsToSelector:@selector(addTarget:action:forControlEvents:)]) {
          if ([active.view isKindOfClass:[UIButton class]]) {
              [((id)active.view) addTarget: n.target action: n.selector forControlEvents: UIControlEventTouchUpInside];
          } else {
              [((id)active.view) addTarget: n.target action: n.selector forControlEvents: UIControlEventEditingChanged];
          }
      } else {
        NSString *error = [NSString stringWithFormat:@"Cannot apply NSInvocation to class %@", NSStringFromClass(active.class)];
        NSAssert(NO, error);
      }
    } else {
      NSAssert(NO, @"Unknown directive in build specifier");
    }
  }
}

@end

@implementation NIPrivateViewInfo
@end


