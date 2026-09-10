#import "VKBaseContentController.h"

// Универсальная заглушка для разделов, которые пока без контента
// (Фотографии, Аудио, Видео, Группы). Заменим позже.
@interface VKPlaceholderViewController : VKBaseContentController
- (id)initWithTitle:(NSString *)title glyph:(NSString *)glyph;
@end
