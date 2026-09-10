#import <Foundation/Foundation.h>

@class VKPost;

// Лайки записей. И likes.add, и likes.delete отвечают «unknown method passed»
// (как groups.join/leave), поэтому лайк живёт только в интерфейсе: счётчик и
// иконка переключаются локально, на сервер ничего не уходит.
@interface VKLikes : NSObject
// Переключает лайк у поста и сразу правит счётчик; changed вызывается после
// изменения, чтобы перерисовать ячейку.
+ (void)togglePost:(VKPost *)post changed:(void (^)(void))changed;
@end
