//***************************************************************************

// Copyright (C) 2008 Realmac Software Ltd
// 
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject
// to the following conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
// ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//***************************************************************************

#import <Foundation/NSObject.h>

//***************************************************************************

/** See http://developer.apple.com/documentation/Cocoa/Conceptual/ModelObjects/ */
@interface RMModelObject : NSObject<NSCopying, NSCoding>

- (BOOL)isEqualToModelObject:(RMModelObject*)other;

@end

//***************************************************************************

@protocol RMModelObjectPropertyChanging

@optional

/// Called when the given property name is about to be changed.  Return YES to accept the change, or NO to reject the change.  If this method is not implemented, it is assumed that all property changes will be accepted.
/** Primitive value types are marshalled into NSNumber/NSValue objects. */
- (BOOL)propertyWillChange:(NSString*)propertyName from:(id)oldValue to:(id)newValue;

/// Called directly after the given property name has changed.
/** Primitive value types are marshalled into NSNumber/NSValue objects. */
- (void)propertyDidChange:(NSString*)propertyName from:(id)oldValue to:(id)newValue;

@end

//***************************************************************************

/// Registers a new RMModelObject_* dynamic class based on the given class.
Class RMModelObjectInitializeDynamicClass(Class mainClass);

//***************************************************************************
