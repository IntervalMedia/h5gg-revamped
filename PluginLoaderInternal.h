#ifndef H5GG_PLUGIN_LOADER_INTERNAL_H
#define H5GG_PLUGIN_LOADER_INTERNAL_H

#import "PluginLoader.h"

NS_ASSUME_NONNULL_BEGIN

typedef void* _Nullable (^H5GGLibraryLoader)(NSString* path,
                                              NSString* _Nullable * _Nullable error);
typedef void (^H5GGLibraryCloser)(void* _Nonnull handle);
typedef Class _Nullable (^H5GGPluginClassResolver)(NSString* className);

@interface H5GGPluginLoader (Internal)

-(instancetype)initWithBundlePath:(NSString*)bundlePath
                    libraryLoader:(H5GGLibraryLoader)libraryLoader
                    libraryCloser:(H5GGLibraryCloser)libraryCloser
                     classResolver:(H5GGPluginClassResolver)classResolver;

@end

NS_ASSUME_NONNULL_END

#endif
