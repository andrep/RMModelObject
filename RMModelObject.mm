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

#import "RMModelObject.h"

#include <objc/runtime.h>
#include <objc/objc-auto.h>

#include <string>
#include <vector>

//***************************************************************************

BOOL RMModelObjectDebuggingEnabled = NO;

#define MOLog(args...) { if(RMModelObjectDebuggingEnabled) NSLog(args); }

//***************************************************************************

#if !defined(TARGET_OS_IPHONE) || TARGET_OS_IPHONE == 0
static inline NSString* NSStringFromCGRect(const CGRect rect)
{
	return NSStringFromRect(NSRectFromCGRect(rect));
}

static inline NSString* NSStringFromCGSize(const CGSize size)
{
	return NSStringFromSize(NSSizeFromCGSize(size));
}

static inline NSString* NSStringFromCGPoint(const CGPoint point)
{
	return NSStringFromPoint(NSPointFromCGPoint(point));
}
#endif

//***************************************************************************

typedef char ObjCPropertyAssignmentMode;
static const char ObjCPropertyAssignmentModeAssign = '\0';
static const char ObjCPropertyAssignmentModeRetain = '&';
static const char ObjCPropertyAssignmentModeCopy = 'C';

//***************************************************************************

// TODO: get rid of this InSituCString class, it's kinda useless
struct InSituCString
{
	const char* cString;
	unsigned length;	// specifically not size_t, to conserve space (this struct really isn't meant for strings that could be 64 bits long...)
	
	inline InSituCString()
	: cString(NULL)
	{
	}
	
	inline InSituCString(const char* aCString)
	: cString(aCString)
	, length(strlen(aCString))
	{
	}
	
	inline InSituCString(const char* aCString, const unsigned aLength)
	: cString(aCString)
	, length(aLength)
	{
	}
	
	inline std::string String() const
	{
		return std::string(cString, length);
	}
};

//---------------------------------------------------------------------------

// TODO: Maybe convert this to a standard C struct and have a ObjCPropertyAttributesMake() function, it's probably a lot more obvious for Cocoa folks
struct ObjCPropertyAttributes
{
	ObjCPropertyAssignmentMode assignmentMode;
	BOOL isReadOnly;
	BOOL isWeak;
	BOOL isDynamic;
	BOOL isSynthesized;
	std::string typeEncoding;
	InSituCString customGetterName;
	InSituCString customSetterName;
	
	inline ObjCPropertyAttributes()
	: assignmentMode(ObjCPropertyAssignmentModeAssign)
	, isReadOnly(NO)
	, isWeak(NO)
	, isDynamic(NO)
	, isSynthesized(NO)
	, typeEncoding()
	, customGetterName()
	, customSetterName()
	{
	}
	
	inline ObjCPropertyAttributes(const char* const propertyAttributesCString)
	{
		isReadOnly = NO;
		isWeak = NO;
		isDynamic = NO;
		isSynthesized = NO;
		
		assignmentMode = ObjCPropertyAssignmentModeAssign;
		
		const char* p = propertyAttributesCString;
		const char* const pEnd = p+strlen(propertyAttributesCString);
		
		for(; p < pEnd; p++)
		{
			const char c = *p;
			
			switch(c)
			{
				case 'R':
					isReadOnly = YES;
					break;
				case 'T':
				{
					p++;
					const char* start = p;
					size_t length = 0;
					while(p < pEnd && *p != ',') 
					{
						length++;
						p++;
					}
					typeEncoding = std::string(start, length);
					break;
				}
				case ObjCPropertyAssignmentModeCopy:
				case ObjCPropertyAssignmentModeRetain:
					NSCAssert2(assignmentMode == ObjCPropertyAssignmentModeAssign,
							   @"Found %c property attribute when we've already seen an assignment mode of %c",
							   c, assignmentMode);
					assignmentMode = c;
					break;
				case 'D':	// Dynamic
					isDynamic = YES;
					break;
				case 'V':	// Synthesized
					isSynthesized = YES;
					while(*p != ',') p++;
					break;
				case 'P':	// Strong reference
					break;
				case 'W':	// Weak reference
					isWeak = YES;
					break;
				case ',':	// Property separator
					break;
//				default:
//					NSCAssert2(NO, @"Encountered unknown property attribute character: %c (%s)", c, propertyAttributesCString);
			}
		}
	}
};

//***************************************************************************

// We need these NewVariableName and NewVariableNameInner macros to generate a unique identifier for each enumerator.
#define NewVariableNameInner(name, line) name ## line
// The NewVariableName macro is needed even though it appears to not do anything, due to the how the C pre-processor works.
#define NewVariableName(name, line) NewVariableNameInner(name, line)

/// Small macro to ease the burden of writing a for() loop to enumerate over all the instance variables in a class.  The first parameter is the name of the newly created ivar, and the second parameter is the object to check (typically just "ivar", and "self", respectively).
#define FOR_ALL_IVARS(ivar, self) \
	unsigned int NewVariableName(numberOfIvars, __LINE__) = 0; \
	const Ivar* const NewVariableName(ivars, __LINE__) = class_copyIvarList([self class], &NewVariableName(numberOfIvars, __LINE__)); \
	void *free_me_using_FREE_FOR_ALL = (void *)NewVariableName(ivars, __LINE__); \
	NSUInteger NewVariableName(i, __LINE__) = 0; \
	for(Ivar ivar = NewVariableName(ivars, __LINE__)[NewVariableName(i, __LINE__)]; \
        NewVariableName(i, __LINE__) < NewVariableName(numberOfIvars, __LINE__); \
        ivar = NewVariableName(ivars, __LINE__)[++NewVariableName(i, __LINE__)])

#define FREE_FOR_ALL free(free_me_using_FREE_FOR_ALL)

//***************************************************************************

template<typename T> static inline T* IvarLocation(id self, Ivar const ivar)
{
	return reinterpret_cast<T*>( (char*)self+ivar_getOffset(ivar) );
}

template<typename T> static inline void GetInstanceVariable(id self, Ivar const ivar, T* const pValue)
{
	*pValue = *IvarLocation<T>(self, ivar);
}

template<typename T> static inline void GetInstanceVariable(id self, const char* const ivarName, T* const pValue)
{
	GetInstanceVariable(self, class_getInstanceVariable([self class], ivarName), pValue);
}

template<typename T> static inline void SetInstanceVariable(id self, Ivar const ivar, const T* const pValue)
{
	*IvarLocation<T>(self, ivar) = *pValue;
}

template<typename T> static inline void SetInstanceVariable(id self, const char* const ivarName, const T* const pValue)
{
	SetInstanceVariable(self, class_getInstanceVariable([self class], ivarName), pValue);
}

template<typename T> static inline T GetRawValue(id self, SEL _cmd)
{
	T value;
	GetInstanceVariable(self, sel_getName(_cmd), &value);
	
	return value;
}

static inline const char* const PropertyNameFromSetterName(Class aClass, SEL setterMethodName)
{
	const char* setterName = sel_getName(setterMethodName);
	
	const char* propertyName = setterName+3;
	const size_t propertyNameLength = strlen(propertyName)-1;	// -1 to strip off the ':' from the end of the selector name
	
	char buffer[propertyNameLength+1]; // +1 for the terminating NUL
	memcpy(buffer, propertyName, propertyNameLength);
	buffer[propertyNameLength] = '\0';
	
	// For a method name that looks like "setFoo:", the property could either be "Foo" or "foo".  First, look up the capitalised version ("Foo"); if that doesn't exist, assume the property name is not capitalised ("foo").
	if(class_getProperty(aClass, buffer) == NULL) buffer[0] = tolower(buffer[0]);
	
	return sel_getName(sel_registerName(buffer));
}

template<typename T> NSValue* NSValueMake(const T* pValue, const char* const typeEncoding)
{
	return [NSValue valueWithBytes:pValue objCType:typeEncoding];
}

#define DEFINE_NSVALUE_MAKE(typeName, uppercasedTypeName) \
template<> NSValue* NSValueMake<typeName>(const typeName* pValue, const char* const) \
{ \
	return [NSNumber numberWith ## uppercasedTypeName:*pValue]; \
}

DEFINE_NSVALUE_MAKE(bool, Bool);
DEFINE_NSVALUE_MAKE(char, Char);
DEFINE_NSVALUE_MAKE(double, Double);
DEFINE_NSVALUE_MAKE(float, Float);
DEFINE_NSVALUE_MAKE(int, Int);
DEFINE_NSVALUE_MAKE(long, Long);
DEFINE_NSVALUE_MAKE(long long, LongLong);
DEFINE_NSVALUE_MAKE(short, Short);
DEFINE_NSVALUE_MAKE(unsigned char, UnsignedChar);
DEFINE_NSVALUE_MAKE(unsigned int, UnsignedInt);
DEFINE_NSVALUE_MAKE(unsigned long, UnsignedLong);
DEFINE_NSVALUE_MAKE(unsigned long long, UnsignedLongLong);
DEFINE_NSVALUE_MAKE(unsigned short, UnsignedShort);

template<typename T> void SetRawValueFast(id const self, SEL _cmd, T value)
{
	const char* const propertyName = PropertyNameFromSetterName([self class], _cmd);
	
	SetInstanceVariable(self, propertyName, &value);
}

template<typename T> void SetRawValueSlow(id const self, SEL _cmd, T value)
{
	const char* const propertyName = PropertyNameFromSetterName([self class], _cmd);
	
	MOLog(@"-[%@ %s]: %s (%s)", NSStringFromClass([self class]), _cmd, propertyName, __PRETTY_FUNCTION__);

	Ivar const ivar = class_getInstanceVariable([self class], propertyName);
	T oldValue;
	GetInstanceVariable(self, ivar, &oldValue);
	
	if(value == oldValue) return;
	
	const char* const ivarTypeEncoding = ivar_getTypeEncoding(ivar);
	
	NSValue* valueObject = NSValueMake(&value, ivarTypeEncoding);
	NSValue* oldValueObject = NSValueMake(&value, ivarTypeEncoding);
	
	NSString* propertyNameObject = [NSString stringWithUTF8String:propertyName];

	if([self respondsToSelector:@selector(propertyWillChange:from:to:)])
	{
		const BOOL shouldChangeProperty = [(id<RMModelObjectPropertyChanging>)self propertyWillChange:propertyNameObject from:oldValueObject to:valueObject];
		if(shouldChangeProperty) SetInstanceVariable(self, propertyName, &value);
	}
	else
	{
		SetInstanceVariable(self, propertyName, &value);
	}
	
	if([self respondsToSelector:@selector(propertyDidChange:from:to:)])
	{
		[(id<RMModelObjectPropertyChanging>)self propertyDidChange:propertyNameObject from:oldValueObject to:valueObject];
	}
}

template<ObjCPropertyAssignmentMode assignmentMode, bool slowMode> void SetRawIdValue(id const self, SEL _cmd, id value)
{
	const char* const propertyName = PropertyNameFromSetterName([self class], _cmd);
	
	id oldValue;
	GetInstanceVariable(self, propertyName, &oldValue);
	
	if(value == oldValue) return;
	
	// Uninitialised intentionally
	NSString* propertyNameObject;
	switch(slowMode)
	{
		case true:
		{
			propertyNameObject = [NSString stringWithUTF8String:propertyName];
			
			if([self respondsToSelector:@selector(propertyWillChange:from:to:)])
			{
				const BOOL shouldChangeProperty = [(id<RMModelObjectPropertyChanging>)self propertyWillChange:propertyNameObject from:oldValue to:value];
				if(!shouldChangeProperty) return;
			}
			
			break;
		}
		case false:
			break;
	}
	
	switch(assignmentMode)
	{
		case ObjCPropertyAssignmentModeAssign:
			break;
		case ObjCPropertyAssignmentModeRetain:
			if(!slowMode) [oldValue release];
			value = [value retain];
			break;
		case ObjCPropertyAssignmentModeCopy:
			if(!slowMode) [oldValue release];
			value = [value copy];
			break;
	}
	
	objc_assign_ivar(value, self, ivar_getOffset(class_getInstanceVariable([self class], propertyName)));
	
	switch(slowMode)
	{
		case true:
			if([self respondsToSelector:@selector(propertyDidChange:from:to:)]) [(id<RMModelObjectPropertyChanging>)self propertyDidChange:propertyNameObject from:oldValue to:value];
			[oldValue release];
			break;
		case false:
			break;
	}
}

static Method GetSetterMethod(Class const self, SEL const selector)
{
	const char* const selectorName = sel_getName(selector);
	
	const size_t selectorNameLength = strlen(selectorName);
	char buffer[selectorNameLength+4+1]; // +4 for "Slow" or "Fast", +1 for terminating NUL
	memcpy(buffer, selectorName, selectorNameLength);
	
	if([self instancesRespondToSelector:@selector(propertyWillChange:from:to:)]
		|| [self instancesRespondToSelector:@selector(propertyDidChange:from:to:)])
	{
		strcpy(buffer+selectorNameLength-1, "Slow:");
	}
	else
	{
		strcpy(buffer+selectorNameLength-1, "Fast:");
	}

	return class_getInstanceMethod(self, sel_registerName(buffer));
}

@implementation RMModelObject

+ (void)load
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bundleDidLoad:) name:NSBundleDidLoadNotification object:nil];
	
	NSAutoreleasePool* pool = [NSAutoreleasePool new];
	
	const int numberOfClasses = objc_getClassList(NULL, 0);
	
	std::vector<Class> classList(numberOfClasses);
	objc_getClassList(&classList[0], numberOfClasses);
	
	for(int i = 0; i < numberOfClasses; i++)
	{
		Class const theClass = classList[i];
		if(class_getSuperclass(theClass) == self) RMModelObjectInitializeDynamicClass(theClass);
	}
	
	[pool drain];
}

+ (void)bundleDidLoad:(NSNotification*)note
{
	NSArray* loadedClassNames = [[note userInfo] objectForKey:NSLoadedClasses];
	if([loadedClassNames count] == 0) return;
	
	for(NSString* className in loadedClassNames)
	{
		Class theClass = objc_getClass([className UTF8String]);
		
		if(class_getSuperclass(theClass) == self) RMModelObjectInitializeDynamicClass(theClass);
	}
}

std::string StripDoubleQuotes(const char* const s)
{
	std::string stripped;
	if(s == NULL) return stripped;
	
	bool insideDoubleQuotes = false;
	for(const char* p = s; *p != '\0'; p++)
	{
		if(*p == '"') insideDoubleQuotes = !insideDoubleQuotes;
		
		if(!insideDoubleQuotes && (*p != '"')) stripped.append(1, *p);
	}
	
	return stripped;
}

int RMTypeEncodingCompare(const char* lhs, const char* rhs)
{
	const std::string& strippedLHS = StripDoubleQuotes(lhs);
	const std::string& strippedRHS = StripDoubleQuotes(rhs);
	
	return strippedLHS.compare(strippedRHS);
}

+ (Method)_assignmentAccessorForTypeEncoding:(const char* const)typeEncoding wantsSetterMethod:(BOOL)wantsSetterMethod
{
	switch(wantsSetterMethod)
	{
		case YES:
		switch(typeEncoding[0])
		{
			case _C_ID:			return GetSetterMethod(self, @selector(_modelObjectSetIdAssign:));
				// _C_CLASS?
				// _C_SEL
			case _C_CHR:		return GetSetterMethod(self, @selector(_modelObjectSetSignedChar:));
			case _C_UCHR:		return GetSetterMethod(self, @selector(_modelObjectSetUnsignedChar:));
			case _C_SHT:		return GetSetterMethod(self, @selector(_modelObjectSetSignedShort:));
			case _C_USHT:		return GetSetterMethod(self, @selector(_modelObjectSetUnsignedShort:));
			case _C_INT:		return GetSetterMethod(self, @selector(_modelObjectSetSignedInt:));
			case _C_UINT:		return GetSetterMethod(self, @selector(_modelObjectSetUnsignedInt:));
			case _C_LNG:		return GetSetterMethod(self, @selector(_modelObjectSetSignedLong:));
			case _C_ULNG:		return GetSetterMethod(self, @selector(_modelObjectSetUnsignedLong:));
			case _C_LNG_LNG:	return GetSetterMethod(self, @selector(_modelObjectSetSignedLongLong:));
			case _C_ULNG_LNG:	return GetSetterMethod(self, @selector(_modelObjectSetUnsignedLongLong:));
			case _C_FLT:		return GetSetterMethod(self, @selector(_modelObjectSetFloat:));
			case _C_DBL:		return GetSetterMethod(self, @selector(_modelObjectSetDouble:));
				// _C_BFLD
				// _C_BOOL
				// _C_VOID?
				// _C_UNDEF
			case _C_PTR:		return GetSetterMethod(self, @selector(_modelObjectSetPointer:));
			case _C_CHARPTR:	return GetSetterMethod(self, @selector(_modelObjectSetCharPointer:));
				// _C_CHARPTR
				// _C_ATOM
				// _C_ARY_B
				// _C_ARY_E
				// _C_UNION_B
				// _C_UNION_E
			case _C_STRUCT_B:
				if(RMTypeEncodingCompare(typeEncoding, @encode(CGRect)) == 0) return GetSetterMethod(self, @selector(_modelObjectSetCGRect:));
				else if(RMTypeEncodingCompare(typeEncoding, @encode(CGSize)) == 0) return GetSetterMethod(self, @selector(_modelObjectSetCGSize:));
				else if(RMTypeEncodingCompare(typeEncoding, @encode(CGPoint)) == 0) return GetSetterMethod(self, @selector(_modelObjectSetCGPoint:));
				else if(RMTypeEncodingCompare(typeEncoding, @encode(NSRange)) == 0) return GetSetterMethod(self, @selector(_modelObjectSetNSRange:));
				// _C_STRUCT_E
				// _C_VECTOR
				// _C_CONST
			default:
				NSAssert1(NO, @"Unknown type encoding: %s", typeEncoding);
		}
		default:
		case NO:
			switch(typeEncoding[0])
		{
			case _C_ID:			return class_getInstanceMethod(self, @selector(_modelObjectGetIdAssign));
				// _C_CLASS
				// _C_SEL
			case _C_CHR:		return class_getInstanceMethod(self, @selector(_modelObjectGetSignedChar));
			case _C_UCHR:		return class_getInstanceMethod(self, @selector(_modelObjectGetUnsignedChar));
			case _C_SHT:		return class_getInstanceMethod(self, @selector(_modelObjectGetSignedShort));
			case _C_USHT:		return class_getInstanceMethod(self, @selector(_modelObjectGetUnsignedShort));
			case _C_INT:		return class_getInstanceMethod(self, @selector(_modelObjectGetSignedInt));
			case _C_UINT:		return class_getInstanceMethod(self, @selector(_modelObjectGetUnsignedInt));
			case _C_LNG:		return class_getInstanceMethod(self, @selector(_modelObjectGetSignedLong));
			case _C_ULNG:		return class_getInstanceMethod(self, @selector(_modelObjectGetUnsignedLong));
			case _C_LNG_LNG:	return class_getInstanceMethod(self, @selector(_modelObjectGetSignedLongLong));
			case _C_ULNG_LNG:	return class_getInstanceMethod(self, @selector(_modelObjectGetUnsignedLongLong));
			case _C_FLT:		return class_getInstanceMethod(self, @selector(_modelObjectGetFloat));
			case _C_DBL:		return class_getInstanceMethod(self, @selector(_modelObjectGetDouble));
				// _C_BFLD
				// _C_BOOL
				// _C_VOID?
				// _C_UNDEF
			case _C_PTR:		return class_getInstanceMethod(self, @selector(_modelObjectGetPointer));
			case _C_CHARPTR:	return class_getInstanceMethod(self, @selector(_modelObjectGetCharPointer));
				// _C_ATOM
				// _C_ARY_B
				// _C_ARY_E
				// _C_UNION_B
				// _C_UNION_E
			case _C_STRUCT_B:
				if(RMTypeEncodingCompare(typeEncoding, @encode(CGRect)) == 0) return class_getInstanceMethod(self, @selector(_modelObjectGetCGRect));
				else if(RMTypeEncodingCompare(typeEncoding, @encode(CGSize)) == 0) return class_getInstanceMethod(self, @selector(_modelObjectGetCGSize));
				else if(RMTypeEncodingCompare(typeEncoding, @encode(CGPoint)) == 0) return class_getInstanceMethod(self, @selector(_modelObjectGetCGPoint));
				else if(RMTypeEncodingCompare(typeEncoding, @encode(NSRange)) == 0) return class_getInstanceMethod(self, @selector(_modelObjectGetNSRange));
				// _C_STRUCT_E
				// _C_VECTOR
				// _C_CONST
			default:
				NSAssert1(NO, @"Unknown type encoding: %s", typeEncoding);
		}
	}
	
	return NULL;
}

#define DEFINE_PRIMITIVE_GETTER_METHOD(typeName, uppercasedTypeName) \
- (typeName)_modelObjectGet ## uppercasedTypeName \
{ \
	return GetRawValue<typeName>(self, _cmd); \
}

#define DEFINE_PRIMITIVE_SETTER_METHOD_SLOW(typeName, uppercasedTypeName) \
- (void)_modelObjectSet ## uppercasedTypeName ## Slow:(typeName)value \
{ \
	SetRawValueSlow<typeName>(self, _cmd, value); \
}

#define DEFINE_PRIMITIVE_SETTER_METHOD_FAST(typeName, uppercasedTypeName) \
- (void)_modelObjectSet ## uppercasedTypeName ## Fast:(typeName)value \
{ \
	SetRawValueFast<typeName>(self, _cmd, value); \
}

#define DEFINE_PRIMITIVE_ACCESSOR_METHODS(typeName, uppercasedTypeName) \
	DEFINE_PRIMITIVE_GETTER_METHOD(typeName, uppercasedTypeName) \
	DEFINE_PRIMITIVE_SETTER_METHOD_SLOW(typeName, uppercasedTypeName) \
	DEFINE_PRIMITIVE_SETTER_METHOD_FAST(typeName, uppercasedTypeName)

static inline bool operator==(const CGPoint lhs, const CGPoint rhs)
{
	return CGPointEqualToPoint(lhs, rhs);
}

static inline bool operator==(const CGRect lhs, const CGRect rhs)
{
	return CGRectEqualToRect(lhs, rhs);
}

static inline bool operator==(const CGSize lhs, const CGSize rhs)
{
	return CGSizeEqualToSize(lhs, rhs);
}

static inline bool operator==(const NSRange lhs, const NSRange rhs)
{
	return NSEqualRanges(lhs, rhs);
}

DEFINE_PRIMITIVE_ACCESSOR_METHODS(signed char, SignedChar);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(signed int, SignedInt);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(signed short, SignedShort);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(signed long, SignedLong);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(signed long long, SignedLongLong);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(unsigned char, UnsignedChar);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(unsigned int, UnsignedInt);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(unsigned short, UnsignedShort);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(unsigned long, UnsignedLong);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(unsigned long long, UnsignedLongLong);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(float, Float);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(double, Double);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(void*, Pointer);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(char*, CharPointer);

DEFINE_PRIMITIVE_ACCESSOR_METHODS(CGPoint, CGPoint);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(CGRect, CGRect);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(CGSize, CGSize);
DEFINE_PRIMITIVE_ACCESSOR_METHODS(NSRange, NSRange);

- (id)_modelObjectGetIdAssign
{
	return GetRawValue<id>(self, _cmd);
}

- (id)_modelObjectGetIdRetain
{
	return [[GetRawValue<id>(self, _cmd) retain] autorelease];
}

- (id)_modelObjectGetIdCopy
{
	return [[GetRawValue<id>(self, _cmd) copy] autorelease];
}

- (void)_modelObjectSetIdAssignSlow:(id)value
{
	SetRawIdValue<ObjCPropertyAssignmentModeAssign, true>(self, _cmd, value);
}

- (void)_modelObjectSetIdRetainSlow:(id)value
{
	SetRawIdValue<ObjCPropertyAssignmentModeRetain, true>(self, _cmd, value);
}

- (void)_modelObjectSetIdCopySlow:(id)value
{
	SetRawIdValue<ObjCPropertyAssignmentModeCopy, true>(self, _cmd, value);
}

- (void)_modelObjectSetIdAssignFast:(id)value
{
	SetRawIdValue<ObjCPropertyAssignmentModeAssign, false>(self, _cmd, value);
}

- (void)_modelObjectSetIdRetainFast:(id)value
{
	SetRawIdValue<ObjCPropertyAssignmentModeRetain, false>(self, _cmd, value);
}

- (void)_modelObjectSetIdCopyFast:(id)value
{
	SetRawIdValue<ObjCPropertyAssignmentModeCopy, false>(self, _cmd, value);
}

static inline id RMAllocateObject(Class self, NSZone* zone)
{
	id allocatedObject = NSAllocateObject(self, 0, zone);
	if(allocatedObject == nil)
	{
		NSLog(@"NSAllocateObject(%@[%p], 0, %@) returned nil", NSStringFromClass([self class]), self, zone);
		
		return nil;
	}
	
	return allocatedObject;
}

+ (id)allocWithZone:(NSZone*)zone
{
	Class dynamicClass = RMModelObjectInitializeDynamicClass(self);
	
	return RMAllocateObject(dynamicClass, zone);
}

static BOOL inline RMClassAddMethod(Class cls, SEL name, IMP imp, const char* types)
{
	if(imp == NULL)
	{
		NSLog(@"RMClassAddMethod() passed a NULL IMP for %s", name);
		return NO;
	}
	
	const BOOL didAddMethod = class_addMethod(cls, name, imp, types);
	if(!didAddMethod) NSLog(@"class_addMethod returned NO for `%s' (IMP=%p, typeEncoding=%s)", name, imp, types);
	
	return didAddMethod;
}

Class RMModelObjectInitializeDynamicClass(Class self)
{
	NSString* className = NSStringFromClass([self class]);
	
	if([className hasPrefix:@"RMModelObject_"]) return objc_getClass([className UTF8String]);
	   
	NSString* dynamicClassName = [NSString stringWithFormat:@"RMModelObject_%@", className];
    if(Class existingDynamicClass = objc_getClass([dynamicClassName UTF8String])) return existingDynamicClass;
	
	Class dynamicClass = objc_allocateClassPair(self, [dynamicClassName UTF8String], 0);
	if(dynamicClass == Nil)
	{
		NSLog(@"objc_allocateClassPair returned NULL");
		return nil;
	}
	
	unsigned numberOfProperties = 0;
	objc_property_t* properties = class_copyPropertyList(self, &numberOfProperties);

	if (numberOfProperties == 0)
		@throw [NSException exceptionWithName:@"InvalidClassException" reason:
				[NSString stringWithFormat:@"You must define at least one dynamic property on the RMModelObject class \"%@\" (or it will just crash anyway)", className] userInfo:nil];
	
	MOLog(@"RMModelObjectInitializeDynamicClass for self=%@ found %u properties", self, numberOfProperties);
	
	for(objc_property_t* property = properties;
		property < properties+numberOfProperties;
		property++)
	{
		const char* const propertyName = property_getName(*property);
		ObjCPropertyAttributes propertyAttributes(property_getAttributes(*property));
		
		if(propertyAttributes.isReadOnly) continue;
		if(!propertyAttributes.isDynamic) continue;
		if(propertyAttributes.isSynthesized) continue;
		
		if(propertyAttributes.isWeak)
		{
			NSCAssert3(NO, @"%s: __weak qualifier not yet supported for class named %@, property named %s, terminating immediately to prevent further unexpected behaviour", __func__, className, propertyName);
		}
		
		const char* const propertyTypeEncoding = propertyAttributes.typeEncoding.c_str();
		if(propertyTypeEncoding == NULL)
		{
			NSCAssert2(NO, @"%s: property type encoding is NULL for property name %s, terminating immediately to prevent further unexpected behaviour", __func__, propertyName);
		}
		
		NSUInteger propertySize = 0;
		NSUInteger propertyAlignment = 0;
		NSGetSizeAndAlignment(propertyTypeEncoding, &propertySize, &propertyAlignment);
		
		MOLog(@"%s has size=%lu (alignment=%lu, %lu)", propertyTypeEncoding, propertySize, propertyAlignment, (NSUInteger)log2(propertyAlignment));
		
		const BOOL didAddIvar = class_addIvar(dynamicClass, propertyName, propertySize, log2(propertyAlignment), propertyTypeEncoding);
		if(!didAddIvar)
		{
			NSLog(@"class_addIvar failed for name=%s, typeEncoding=%s, size=%lu, alignment=%lu", propertyName, propertyTypeEncoding, propertySize, propertyAlignment);
			free(properties);
			return nil;
		}
		
		const char* const getterName = propertyName;
		
		size_t bufferSize = strlen(propertyName)+3+1+1;  // +3 for "set", +1 for ":", +1 for NUL
		char buffer[bufferSize];
		const int charactersPrinted = snprintf(buffer, bufferSize, "set%c%s:", islower(propertyName[0]) ? toupper(propertyName[0]) : propertyName[0], propertyName+1);
		if(charactersPrinted != (int)bufferSize-1)
		{
			NSLog(@"snprintf() of %c%s: wrote %d characters, which is different from the buffer size of %zu-1",
				  islower(propertyName[0]) ? toupper(propertyName[0]) : propertyName[0], propertyName+1, charactersPrinted, bufferSize);
			free(properties);
			return nil;
		}
		
		const char* const setterName = buffer;
		
		Method getter = NULL;
		if(class_getInstanceMethod(self, sel_registerName(getterName)) == NULL)
		{
			if(propertyAttributes.assignmentMode == ObjCPropertyAssignmentModeAssign) getter = [self _assignmentAccessorForTypeEncoding:propertyTypeEncoding wantsSetterMethod:NO];
			else if(propertyAttributes.assignmentMode == ObjCPropertyAssignmentModeRetain) getter = class_getInstanceMethod(self, @selector(_modelObjectGetIdRetain));
			else if(propertyAttributes.assignmentMode == ObjCPropertyAssignmentModeCopy) getter = class_getInstanceMethod(self, @selector(_modelObjectGetIdCopy));
			
			RMClassAddMethod(dynamicClass, sel_registerName(getterName), method_getImplementation(getter), method_getTypeEncoding(getter));
		}
			
		Method setter = NULL;
		if(propertyAttributes.assignmentMode == ObjCPropertyAssignmentModeAssign) setter = [self _assignmentAccessorForTypeEncoding:propertyTypeEncoding wantsSetterMethod:YES];
		else if(propertyAttributes.assignmentMode == ObjCPropertyAssignmentModeRetain) setter = GetSetterMethod(self, @selector(_modelObjectSetIdRetain:));
		else if(propertyAttributes.assignmentMode == ObjCPropertyAssignmentModeCopy) setter = GetSetterMethod(self, @selector(_modelObjectSetIdCopy:));
		
		RMClassAddMethod(dynamicClass, sel_registerName(setterName), method_getImplementation(setter), method_getTypeEncoding(setter));
		
		class_addProtocol(dynamicClass, @protocol(NSCoding));
		class_addProtocol(dynamicClass, @protocol(NSCopying));
	}

	objc_registerClassPair(dynamicClass);
	
	free(properties);
	return dynamicClass;
}

- (void)dealloc
{
	/*unsigned int numberOfIvars = 0;
	Ivar* ivars = class_copyIvarList([self class], &numberOfIvars);
	
	for(const Ivar* p = ivars; p < ivars+numberOfIvars; p++)
	{
		Ivar const ivar = *p;
	}*/
	
	FOR_ALL_IVARS(ivar, self)
	{
		MOLog(@"%@: deallocating %s...", NSStringFromClass([self class]), ivar_getName(ivar));
		if(ivar_getTypeEncoding(ivar)[0] == _C_ID) [self setValue:nil forKey:[NSString stringWithUTF8String:ivar_getName(ivar)]];
	}
	
	FREE_FOR_ALL;
	[super dealloc];
}

#pragma mark NSCopying

static id CopyObjectInto(id self, id copiedObject, NSZone* zone, const BOOL mutableCopy)
{
	if (!copiedObject)
		copiedObject = [[[self class] alloc] init];
	
	MOLog(@"copied object size=%lu, self size=%lu", class_getInstanceSize([copiedObject class]), class_getInstanceSize([self class]));
	
	FOR_ALL_IVARS(ivar, self)
	{
		const char* ivarName = ivar_getName(ivar);
		
		objc_property_t property = class_getProperty([self class], ivarName);
		if(property == NULL) continue;
		
		const ptrdiff_t ivarOffset = ivar_getOffset(ivar);
		
		MOLog(@"about to copy %s (offset=%ld)...", ivarName, ivarOffset);
		
		// We assume that the property to copy is of type id: if it isn't, it doesn't matter anyway since we figure out the real size of the object using NSGetSizeAndAlignment() and do an approprate memcpy.  If it's a proper id, it simplifies the code a bit since we don't need to cast void*'s to ids.
		id* destinationIvarLocation = reinterpret_cast<id*>( (char*)copiedObject+ivarOffset );
		id* sourceIvarLocation = reinterpret_cast<id*>( (char*)self+ivarOffset );
		
		ObjCPropertyAttributes propertyAttributes(property_getAttributes(property));
		switch(propertyAttributes.assignmentMode)
		{
			case ObjCPropertyAssignmentModeAssign:
			{
				NSUInteger ivarSize = 0;
				NSUInteger ivarAlignment = 0;
				NSGetSizeAndAlignment(ivar_getTypeEncoding(ivar), &ivarSize, &ivarAlignment);
				
				MOLog(@"pre-memcpy() from %p (%p+%ld) to %p, size=%lu", sourceIvarLocation, self, ivarOffset, destinationIvarLocation, ivarSize);
				
				memcpy(destinationIvarLocation, sourceIvarLocation, ivarSize);
				
				MOLog(@"post-memcpy()");
				break;
			}
			case ObjCPropertyAssignmentModeRetain:
				*destinationIvarLocation = [*sourceIvarLocation retain];
				break;
			case ObjCPropertyAssignmentModeCopy:
				if(mutableCopy && [*sourceIvarLocation respondsToSelector:@selector(mutableCopyWithZone:)]) *destinationIvarLocation = [*sourceIvarLocation mutableCopy];
				else *destinationIvarLocation = [*sourceIvarLocation copy];
				break;
		}
		
		MOLog(@"ivar %s copied", ivarName);
	}
	
	MOLog(@"About to return copied object");
	
	// TODO: call [super copy]
	
	FREE_FOR_ALL;
	return copiedObject;
}

- (id)copyInto:(id)receiver withZone:(NSZone*)zone
{
	return CopyObjectInto(self, receiver, zone, NO);
}

- (id)copyWithZone:(NSZone*)zone
{
	return CopyObjectInto(self, nil, zone, NO);
}

- (id)mutableCopyWithZone:(NSZone*)zone
{
	return CopyObjectInto(self, nil, zone, YES);
}

#pragma mark NSCoding

- (id)initWithCoder:(NSCoder*)decoder
{
	MOLog(@"initWithCoder 1");
	
	self = [super init];
	if(self == nil) return nil;
	
	MOLog(@"initWithCoder 2");
	
	unsigned int numberOfIvars = 0;
	Ivar* ivars = class_copyIvarList([self class], &numberOfIvars);
		
	if([decoder allowsKeyedCoding])
	{
		for(const Ivar* p = ivars; p < ivars+numberOfIvars; p++)
		{
			Ivar const ivar = *p;
			
			NSString* ivarNameString = [NSString stringWithUTF8String:ivar_getName(ivar)];
			
			if([decoder containsValueForKey:ivarNameString])
			{
				id object = [decoder decodeObjectForKey:ivarNameString];
				[self setValue:object forKey:ivarNameString];
				
				MOLog(@"Setting object %p (%@) for key %@", object, object, ivarNameString);
			}
		}
	}
	else
	{
		id object = [decoder decodeObject];
		
		if(object == nil)
		{
			MOLog(@"-[%@ initWithCoder:]: unkeyed decoder doesn't have an initial object", NSStringFromClass([self class]));
			
			[self release];
			free(ivars);
			return nil;
		}
		
		NSDictionary* dictionary = [object isKindOfClass:[NSDictionary class]] ? (NSDictionary*)object : nil;
		if(dictionary == nil)
		{
			MOLog(@"-[%@ initWithCoder:]: unkeyed decoder's initial object is not an NSDictionary", NSStringFromClass([self class]));
			
			[self release];
			free(ivars);
			return nil;
		}
		
		for(const Ivar* p = ivars; p < ivars+numberOfIvars; p++)
		{
			Ivar const ivar = *p;
			
			NSString* ivarNameString = [NSString stringWithUTF8String:ivar_getName(ivar)];
			
			if([dictionary objectForKey:ivarNameString])
			{
				id object = [dictionary objectForKey:ivarNameString];
				[self setValue:object forKey:ivarNameString];
			}
		}
	}
	
	free(ivars);
	return self;
}

- (void)encodeWithCoder:(NSCoder*)encoder
{
	// This is only used if the encoder doesn't support keyed coding
	NSMutableDictionary* encodingDictionary = [NSMutableDictionary dictionary];
	
	FOR_ALL_IVARS(ivar, self)
	{
		NSString* ivarNameString = [NSString stringWithUTF8String:ivar_getName(ivar)];
		
		id object = [self valueForKey:ivarNameString];
		
		MOLog(@"encoding property name %@: %@ (%@)", ivarNameString, object, NSStringFromClass([object class]));
		
		if(object)
		{
			if([encoder allowsKeyedCoding]) [encoder encodeObject:object forKey:ivarNameString];
			else [encodingDictionary setObject:object forKey:ivarNameString];
		}
	}
	
	if(![encoder allowsKeyedCoding]) [encoder encodeObject:encodingDictionary];
	FREE_FOR_ALL;
}

#pragma mark NSObject

- (NSString*)description
{
	NSMutableString* const description = [NSMutableString string];
	
	[description appendFormat:@"<%@ %p: ", NSStringFromClass([[self superclass] class]), self];
	
	NSString* separator = @"\n	   ";
	
	FOR_ALL_IVARS(ivar, self)
	{
		const char* const ivarName = ivar_getName(ivar);
		
		objc_property_t const property = class_getProperty([self class], ivarName);
		if(property == NULL) continue;
		
		const ptrdiff_t ivarOffset = ivar_getOffset(ivar);
		
		MOLog(@"about to describe %s (offset=%ld)...", ivarName, ivarOffset);
		
		// We assume that the property to inspect is of type id: if it isn't, it doesn't matter anyway since we figure out the real size of the object using NSGetSizeAndAlignment() and do an approprate memcmp.  If it's a proper id, it simplifies the code a bit since we don't need to cast void*'s to ids.
		id* ivarLocation = reinterpret_cast<id*>( (char*)self+ivarOffset );
		
		const char* const ivarTypeEncoding = ivar_getTypeEncoding(ivar);
		NSString* format = nil;
		switch(ivarTypeEncoding[0])
		{
			case _C_ID:
			{
				id const object = (id)*ivarLocation;
				if ([object respondsToSelector:@selector(descriptionWithLocale:indent:)])
					[description appendFormat:@"%@%s = %@", separator, ivarName, [object descriptionWithLocale:nil indent:1]];
				else
					[description appendFormat:@"%@%s = %@", separator, ivarName, object];
				break;
			}
			case _C_INT:	format = @"%i"; break;
			case _C_UINT:	format = @"%u"; break;
			case _C_SHT:	format = @"%hi"; break;
			case _C_USHT:	format = @"%hu"; break;
			case _C_LNG:	format = @"%li"; break;
			case _C_ULNG:	format = @"%lu"; break;
			case _C_CHR:	format = @"%hhi"; break;
			case _C_UCHR:	format = @"%hhu"; break;
			case _C_LNG_LNG:	format = @"%lli"; break;
			case _C_ULNG_LNG:	format = @"%llu"; break;
			case _C_FLT:	format = @"%f"; break;
			case _C_DBL:	format = @"%f"; break;
			case _C_STRUCT_B:
				if(RMTypeEncodingCompare(ivarTypeEncoding, @encode(CGRect)) == 0)
				{
					[description appendFormat:@"%@%s = (rect) %@", separator, ivarName, NSStringFromCGRect(*(CGRect*)ivarLocation)];
					break;
				}
				else if(RMTypeEncodingCompare(ivarTypeEncoding, @encode(CGSize)) == 0)
				{
					[description appendFormat:@"%@%s = (size) %@", separator, ivarName, NSStringFromCGSize(*(CGSize*)ivarLocation)];
					break;
				}
				else if(RMTypeEncodingCompare(ivarTypeEncoding, @encode(CGPoint)) == 0)
				{
					[description appendFormat:@"%@%s = (point) %@", separator, ivarName, NSStringFromCGPoint(*(CGPoint*)ivarLocation)];
					break;
				}
				else if(RMTypeEncodingCompare(ivarTypeEncoding, @encode(NSRange)) == 0)
				{
					[description appendFormat:@"%@%s = (range) %@", separator, ivarName, NSStringFromRange(*(NSRange*)ivarLocation)];
					break;
				}
			default:
				[description appendFormat:@"%@%s = ?", separator, ivarName];
				break;
		}
		
		if(format != nil)
		{
			[description appendFormat:@"%@%s = ", separator, ivarName];
			
			if (ivarTypeEncoding[0] == _C_FLT)
				[description appendFormat:format, *((float*)ivarLocation)]; // else you get 0.0000000
			else if (ivarTypeEncoding[0] == _C_DBL)
				[description appendFormat:format, *((double*)ivarLocation)]; // else you get 0.0000000
			else
				[description appendFormat:format, *ivarLocation];
		}
		separator = @"\n	";
	}
	
	[description appendFormat:@">"];
	
	FREE_FOR_ALL;
	return description;
}

- (BOOL)isEqual:(id)other
{
	if([other isKindOfClass:[self class]]) return [self isEqualToModelObject:other];
	else return NO;
}

- (BOOL)isEqualToModelObject:(RMModelObject*)other
{
	FOR_ALL_IVARS(ivar, self)
	{
		const char* ivarName = ivar_getName(ivar);
		
		objc_property_t property = class_getProperty([self class], ivarName);
		if(property == NULL) continue;
		
		const ptrdiff_t ivarOffset = ivar_getOffset(ivar);
		
		MOLog(@"about to check equality of %s (offset=%ld)...", ivarName, ivarOffset);
		
		// We assume that the property to inspect is of type id: if it isn't, it doesn't matter anyway since we figure out the real size of the object using NSGetSizeAndAlignment() and do an approprate memcmp.  If it's a proper id, it simplifies the code a bit since we don't need to cast void*'s to ids.
		id* sourceIvarLocation = reinterpret_cast<id*>( (char*)self+ivarOffset );
		id* otherIvarLocation = reinterpret_cast<id*>( (char*)other+ivarOffset );
		
		const char* const ivarTypeEncoding = ivar_getTypeEncoding(ivar);
		switch(ivarTypeEncoding[0])
		{
			case _C_ID:
			{
				if(*sourceIvarLocation == nil && *otherIvarLocation == nil) continue;
				
				else if(![*sourceIvarLocation isEqual:*otherIvarLocation])
				{
					MOLog(@"isEqual: for %s (type id) returned NO: src=%@, other=%@",
						  ivarName, *sourceIvarLocation, *otherIvarLocation);
					FREE_FOR_ALL;
					return NO;
				}
				break;
			}
			default:
			{
				NSUInteger ivarSize = 0;
				NSUInteger ivarAlignment = 0;
				NSGetSizeAndAlignment(ivar_getTypeEncoding(ivar), &ivarSize, &ivarAlignment);
				
				MOLog(@"pre-memcmp() of %p (%p+%ld) with %p, size=%lu",
					  sourceIvarLocation, self, ivarOffset, otherIvarLocation, ivarSize);
				
				const int memcmpResult = memcmp(sourceIvarLocation, otherIvarLocation, ivarSize);
				if(memcmpResult != 0)
				{
					MOLog(@"isEqual: for %s (type %s) returned NO", ivarName, ivarTypeEncoding);
					FREE_FOR_ALL;
					return NO;
				}
				
				MOLog(@"post-memcmp()");
				break;
			}
		}
		
		MOLog(@"ivar %s passed equality check", ivarName);
	}
	
	FREE_FOR_ALL;
	return YES;
}

- (NSUInteger)hash
{
	// This is an incredibly braindead hash function, but see <http://developer.apple.com/documentation/Cocoa/Reference/Foundation/Protocols/NSObject_Protocol/Reference/NSObject.html#//apple_ref/doc/uid/20000052-BBCGFFCH>.  I quote: "If a mutable object is added to a collection that uses hash values to determine the object’s position in the collection, the value returned by the hash method of the object must not change while the object is in the collection. Therefore, either the hash method must not rely on any of the object’s internal state information or you must make sure the object’s internal state information does not change while the object is in the collection."  While this sounds completely braindead to me, I'm erring on the safe side rather than risking Cocoa non-compliance.  If you have any hints for this, please let me know.
	
	NSUInteger hash = 0;
	
	FOR_ALL_IVARS(ivar, self) hash += (NSUInteger)ivar;
	
	FREE_FOR_ALL;
	return hash;
}

@end

//***************************************************************************
