#ifndef H5GG_PREFERENCES_STORE_INTERNAL_H
#define H5GG_PREFERENCES_STORE_INTERNAL_H

#import "PreferencesStore.h"

NS_ASSUME_NONNULL_BEGIN

typedef NSString* _Nonnull (^H5GGTimestampProvider)(void);

@interface H5GGPreferencesStore (Internal)

-(instancetype)initWithUserDefaults:(NSUserDefaults*)defaults
                   timestampProvider:(H5GGTimestampProvider)timestampProvider;

@end

NS_ASSUME_NONNULL_END

#endif
