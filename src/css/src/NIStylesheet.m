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

#import "NIStylesheet.h"

#import "NICSSParser.h"
#import "NICSSRuleset.h"
#import "NIStyleable.h"
#import "NimbusCore.h"
#import "NICSSResourceResolverDelegate.h"
#import "NIDOM.h"

#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "Nimbus requires ARC support."
#endif

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@interface NICSSScopeDefinition : NSObject
@property (nonatomic,strong) NSString *fullScope;
@property (nonatomic,strong) NSArray *orderedList;
@end
@implementation NICSSScopeDefinition
-(NSString *)description { return self.fullScope; }
@end
///////////////////////////////////////////////////////////////////////////////////////////////////

NSString* const NIStylesheetDidChangeNotification = @"NIStylesheetDidChangeNotification";
static Class _rulesetClass;
static id<NICSSResourceResolverDelegate> _resolver;


static const int numPreallocatedRulesets = 100;

@interface NIStylesheet() {
  NICSSRuleset* _preallocatedRulesets[numPreallocatedRulesets];
}
@property (nonatomic, assign) int preallocatedRulesetIndex;
@property (nonatomic, readonly, copy) NSDictionary* rawRulesets;
@property (nonatomic, readonly, copy) NSDictionary* significantScopeToScopes;
@end

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@implementation NIStylesheet

@synthesize rawRulesets = _rawRulesets;
@synthesize significantScopeToScopes = _significantScopeToScopes;

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Rule Sets

///////////////////////////////////////////////////////////////////////////////////////////////////
- (id)init {
  if ((self = [super init])) {
    [self setupPreallocatedRulesets];
  }
  return self;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
-(void)setupPreallocatedRulesets {
  for (int i = 0; i < numPreallocatedRulesets; i++) {
    _preallocatedRulesets[i] = [[[NIStylesheet rulesetClass] alloc] init];
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
-(NICSSRuleset *)getRuleset {
  NICSSRuleset *r;
  if (self.preallocatedRulesetIndex < numPreallocatedRulesets) {
    r = _preallocatedRulesets[self.preallocatedRulesetIndex];
  } else {
    r = [[[NIStylesheet rulesetClass] alloc] init];
  }
  
  [r reset];
  self.preallocatedRulesetIndex++;
  return r;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
-(void)resetPreallocatedRulesetIndex {
  self.preallocatedRulesetIndex = 0;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
// Builds a map of significant scopes to full scopes.
//
// For example, consider the following rulesets:
//
// .root UIButton {
// }
// .apple UIButton {
// }
// UIButton UIView {
// }
// UIView {
// }
//
// The generated scope map will look like:
//
// UIButton => (.root UIButton, .apple UIButton)
// UIView => (UIButton UIView, UIView)
//
- (void)rebuildSignificantScopeToScopes {
  NSMutableDictionary* significantScopeToScopes =
  [[NSMutableDictionary alloc] initWithCapacity:[_rawRulesets count]];

  for (NSString* scope in _rawRulesets) {
    NSArray* parts = [scope componentsSeparatedByString:@" "];
    NSString* mostSignificantScopePart = [parts lastObject];

    // TODO (jverkoey Oct 6, 2011): We should respect CSS specificity. Right now this will
    // give higher precedance to newer styles. Instead, we should prefer styles that have more
    // selectors.
    NICSSScopeDefinition *scopeDef = [[NICSSScopeDefinition alloc] init];
    scopeDef.fullScope = scope;
    scopeDef.orderedList = parts;
    
    NSMutableArray* scopes = [significantScopeToScopes objectForKey:mostSignificantScopePart];
    if (nil == scopes) {
      scopes = [[NSMutableArray alloc] initWithObjects:scopeDef, nil];
      [significantScopeToScopes setObject:scopes forKey:mostSignificantScopePart];
      
    } else {
      [scopes addObject:scopeDef];
    }
  }

  // Poor mans importance sorting of selectors
  [significantScopeToScopes enumerateKeysAndObjectsUsingBlock:^(NSString *significantScope, NSMutableArray *scopes, BOOL *stop) {
    [scopes sortUsingComparator:^NSComparisonResult(NICSSScopeDefinition* scope1, NICSSScopeDefinition *scope2) {
      return scope1.orderedList.count - scope2.orderedList.count;
    }];
  }];

  _significantScopeToScopes = [significantScopeToScopes copy];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)ruleSetsDidChange {
  [self rebuildSignificantScopeToScopes];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSNotifications


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Public Methods


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)loadFromPath:(NSString *)path {
  return [self loadFromPath:path pathPrefix:nil delegate:nil];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)loadFromPath:(NSString *)path pathPrefix:(NSString *)pathPrefix {
  return [self loadFromPath:path pathPrefix:pathPrefix delegate:nil];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)loadFromPath:(NSString *)path
          pathPrefix:(NSString *)pathPrefix
            delegate:(id<NICSSParserDelegate>)delegate {
  BOOL loadDidSucceed = NO;

  @synchronized(self) {
    _rawRulesets = nil;
    _significantScopeToScopes = nil;

    NICSSParser* parser = [[NICSSParser alloc] init];

    NSDictionary* results = [parser dictionaryForPath:path
                                           pathPrefix:pathPrefix
                                             delegate:delegate];
    if (nil != results && ![parser didFailToParse]) {
      _rawRulesets = results;
      loadDidSucceed = YES;
    }

    if (loadDidSucceed) {
      [self ruleSetsDidChange];
    }
  }

  return loadDidSucceed;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)addStylesheet:(NIStylesheet *)stylesheet {
  NIDASSERT(nil != stylesheet);
  if (nil == stylesheet) {
    return;
  }

  @synchronized(self) {
    NSMutableDictionary* compositeRuleSets = [self.rawRulesets mutableCopy];

    BOOL ruleSetsDidChange = NO;

    for (NSString* selector in stylesheet.rawRulesets) {
      NSDictionary* incomingRuleSet   = [stylesheet.rawRulesets objectForKey:selector];
      NSDictionary* existingRuleSet = [self.rawRulesets objectForKey:selector];

      // Don't bother adding empty rulesets.
      if ([incomingRuleSet count] > 0) {
        ruleSetsDidChange = YES;

        if (nil == existingRuleSet) {
          // There is no rule set of this selector - simply add the new one.
          [compositeRuleSets setObject:incomingRuleSet forKey:selector];
          continue;
        }

        NSMutableDictionary* compositeRuleSet = [existingRuleSet mutableCopy];
        // Add the incoming rule set entries, overwriting any existing ones.
        [compositeRuleSet addEntriesFromDictionary:incomingRuleSet];

        [compositeRuleSets setObject:compositeRuleSet forKey:selector];
      }
    }

    _rawRulesets = [compositeRuleSets copy];

    if (ruleSetsDidChange) {
      [self ruleSetsDidChange];
    }
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Applying Styles to Views


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)applyRuleSet:(NICSSRuleset *)ruleSet toView:(UIView *)view inDOM: (NIDOM*)dom {
  if ([view respondsToSelector:@selector(applyStyleWithRuleSet:inDOM:)]) {
    [(id<NIStyleable>)view applyStyleWithRuleSet:ruleSet inDOM:dom];
  }
}


- (void)applyStyleToView:(UIView *)view withSelectors:(NSArray *)selectors andPseudoSelectors:(NSArray *)pseudoSelectors inDOM:(NIDOM *)dom {
  NICSSRuleset *ruleset = [self rulesetForView:view withSelectors:selectors inDOM:dom];
  if (ruleset) {
    [self applyRuleSet:ruleset toView:view inDOM:dom];
  }

  for (NSString *pseudoSelector in pseudoSelectors) {
    if ([view respondsToSelector:@selector(applyStyleWithRuleSet:forPseudoClass:inDOM:)]) {
      NSRange r = [pseudoSelector rangeOfString:@":"];
      NICSSRuleset *pseudoRuleset = [self rulesetForView:view withSelectors:@[pseudoSelector] inDOM:dom];
      if (pseudoRuleset) {
        [(id<NIStyleable>)view applyStyleWithRuleSet:pseudoRuleset
                                      forPseudoClass:[pseudoSelector substringFromIndex:r.location+1]
                                               inDOM:dom];
      }
    }
  }
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (NICSSRuleset*) rulesetWithSelectors: (NSArray*) selectors
{
  if ([selectors count] > 0) {
    // Gather all of the rule sets for this view into a composite rule set.
    NICSSRuleset *ruleSet = [self getRuleset];
    
    // Composite the rule sets into one.
    for (NSString* selector in selectors) {
      [ruleSet addEntriesFromDictionary:[_rawRulesets objectForKey:selector]];
    }
    
    return ruleSet;
  }
  
  return nil;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (NICSSRuleset *)rulesetForClassName:(NSString *)className {
  return [self rulesetWithSelectors: @[className]];
}

static NSMutableArray * matchingSelectors;
///////////////////////////////////////////////////////////////////////////////////////////////////
- (NICSSRuleset*) rulesetForView: (UIView*) view withSelectors: (NSArray*) shortSelectors inDOM: (NIDOM*) dom {

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        matchingSelectors = [NSMutableArray array];
    });
    [matchingSelectors removeAllObjects];

  for (NSString *selector in shortSelectors) {

    NSArray* selectors = [_significantScopeToScopes objectForKey:selector];

    for (NICSSScopeDefinition *sd in selectors) {
        if (sd.orderedList == nil || sd.orderedList.count == 1) {
            [matchingSelectors addObject:sd.fullScope];
        } else {
            // Ok, now we've got to walk the hierarchy looking for a match. lastObject is className, but the others are unknown
            UIView *matchView = [view superview];
            int ruleIx = sd.orderedList.count - 2;
            while (matchView && ruleIx >= 0) {
                NSString *currentMatch = [sd.orderedList objectAtIndex:ruleIx];
                BOOL mustMatch = NO;
                if ([currentMatch isEqualToString:@">"]) {
                    ruleIx--;
                    if (ruleIx < 0) {
                        break; // > at the root. Match I suppose.
                    }
                    currentMatch = [sd.orderedList objectAtIndex:ruleIx];
                    mustMatch = YES;
                }
                char first = [currentMatch characterAtIndex:0];
                BOOL isObjCClass = (first != '#' && first != '.');
                if ((!isObjCClass && [dom view: matchView hasShortSelector: currentMatch]) ||
                    (isObjCClass && [NSStringFromClass([matchView class]) isEqualToString:currentMatch])) {
                    ruleIx--;
                } else if (mustMatch) {
                    // Didn't match, bail.
                    break;
                }
                matchView = [matchView superview];
            }
            if (ruleIx < 0) {
                [matchingSelectors addObject:sd.fullScope];
            }
        }
    }
  }
  return [self rulesetWithSelectors:matchingSelectors];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (NSSet *)dependencies {
  return [_rawRulesets objectForKey:kDependenciesSelectorKey];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
+(Class)rulesetClass {
  return _rulesetClass ?: [NICSSRuleset class];
}

///////////////////////////////////////////////////////////////////////////////////////////////////
+(void)setRulesetClass:(Class)rulesetClass {
  _rulesetClass = rulesetClass;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
+(id<NICSSResourceResolverDelegate>)resourceResolver {
    return _resolver;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
+(void)setResourceResolver: (id<NICSSResourceResolverDelegate>) resolver {
    _resolver = resolver;
}


@end
