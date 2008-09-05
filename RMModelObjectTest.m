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

#import <SenTestingKit/SenTestingKit.h>

#import "RMModelObject.h"

//***************************************************************************

@interface RMModelObjectTest : RMModelObject
{
	int _synthesizedProperty;
}

// Primitive Types
@property BOOL b;
@property char c;
@property unsigned char uc;
@property int i;
@property unsigned int ui;
@property short s;
@property unsigned short us;
@property long l;
@property unsigned long ul;
@property long long ll;
@property unsigned long long ull;
@property float f;
@property double d;

// Typical Cocoa aggregate types
@property NSRect nsrect;
@property NSRange nsrange;
@property NSPoint nspoint;
@property NSSize nssize;

@property int synthesizedProperty;

// Objects
@property (assign) NSString* assignedString;
@property (retain) NSString* retainedString;
@property (copy) NSString* copiedString;
@property (retain, readonly) NSString* readOnlyString;
@property (retain) NSSet* set;	// Testing that 'set' should be a getter name, not a setter
//@property (retain, getter=foo, setter=bar:) NSString* customAccessorString;	// Custom getter/setter names not supported yet

@end

//***************************************************************************

@implementation RMModelObjectTest

@synthesize synthesizedProperty = _synthesizedProperty;

@dynamic b, c, uc, i, ui, s, us, l, ul, ll, ull, f, d, nsrect, nsrange, nspoint, nssize;
@dynamic assignedString, retainedString, copiedString, readOnlyString, set;

@end

//***************************************************************************

@interface RMModelObjectTestCase : SenTestCase

@end

//---------------------------------------------------------------------------

@implementation RMModelObjectTestCase

- (void)testModelObject
{
	NSAutoreleasePool* pool = [NSAutoreleasePool new];
	
	RMModelObjectTest* testObject = [[RMModelObjectTest alloc] init];
	
	//
	
	STAssertEquals(testObject.i, 0, nil);
	
	testObject.i = 69;
	STAssertEquals(testObject.i, 69, nil);
	
	//
	
	STAssertEqualsWithAccuracy(testObject.f, 0.0f, FLT_EPSILON, nil);
	
	testObject.f = 1.618f;
	STAssertEqualsWithAccuracy(testObject.f, 1.618f, FLT_EPSILON, nil);
	
	//
	
	STAssertEqualsWithAccuracy(testObject.d, 0.0, DBL_EPSILON, nil);
	
	testObject.d = 71.0;
	STAssertEqualsWithAccuracy(testObject.d, 71.0, DBL_EPSILON, nil);
	
	//
	
	STAssertEquals(testObject.b, NO, nil);
	
	testObject.b = YES;
	STAssertEquals(testObject.b, YES, nil);
	
	//
	
	unsigned long long ll1 = testObject.ull;
	STAssertEquals(ll1, 0ULL, nil);
	
	testObject.ull = 18446744073709551610ULL;
	STAssertEquals(testObject.ull, 18446744073709551610ULL, nil);
	
	//
	
	NSString* fooString = [[NSString alloc] initWithUTF8String:"Foo"];
	if(![NSGarbageCollector defaultCollector]) STAssertEquals([fooString retainCount], 1UL, nil);
	
	testObject.assignedString = fooString;
	STAssertEquals(testObject.assignedString, fooString, nil);
	STAssertEqualObjects(testObject.assignedString, fooString, nil);
	if(![NSGarbageCollector defaultCollector]) STAssertEquals([testObject.assignedString retainCount], 1UL, nil);
	
	//
	
	id fooStringId = [[NSString alloc] initWithUTF8String:"Foo"];
	STAssertEqualObjects(testObject.assignedString, fooStringId, nil);
	
	//
	
	NSString* barString = [[NSString alloc] initWithUTF8String:"Bar"];
	if(![NSGarbageCollector defaultCollector]) STAssertEquals([barString retainCount], 1UL, nil);
	
	testObject.retainedString = barString;
	STAssertEquals(testObject.retainedString, barString, nil);
	STAssertTrue(testObject.retainedString == barString, nil);
	if(![NSGarbageCollector defaultCollector]) STAssertEquals([barString retainCount], 4UL, nil);
	if(![NSGarbageCollector defaultCollector]) STAssertEquals([testObject.retainedString retainCount], 5UL, nil);
	
	//
	
	NSMutableString* bazString = [[NSMutableString alloc] initWithUTF8String:"Baz"];
	testObject.copiedString = bazString;
	STAssertFalse(testObject.copiedString == bazString, nil);
	STAssertEqualObjects(testObject.copiedString, bazString, nil);
	
	//
	
	STAssertEqualObjects(testObject.set, nil, nil);
	
	testObject.set = [NSSet setWithObject:@"Hello"];
	NSSet* anotherSet = [NSSet setWithObjects:@"Hello", nil];
	STAssertEqualObjects(testObject.set, anotherSet, nil);
	
	RMModelObjectTest* copiedObject = [[testObject copy] autorelease];
	STAssertTrue([testObject isEqual:copiedObject], nil);
	
	STAssertEquals(copiedObject.i, 69, nil);
	STAssertEquals(copiedObject.b, YES, nil);
	STAssertEquals(copiedObject.ull, 18446744073709551610ULL, nil);
	
	STAssertEquals(copiedObject.assignedString, fooString, nil);
	STAssertEqualObjects(copiedObject.assignedString, fooString, nil);
	if(![NSGarbageCollector defaultCollector]) STAssertEquals([copiedObject.assignedString retainCount], 1UL, nil);
	
	STAssertEquals(copiedObject.retainedString, barString, nil);
	if(![NSGarbageCollector defaultCollector]) STAssertTrue([copiedObject.retainedString retainCount] > 2UL, nil);
	
	STAssertFalse(copiedObject.copiedString == bazString, nil);
	STAssertEquals(copiedObject.copiedString, testObject.copiedString, nil);	// Dependent on immutable -[NSString copy] simply bumping the retain count
	
	//
	
	Class archiverClass = [NSArchiver class];
	for(; archiverClass != [NSKeyedArchiver class]; archiverClass = [NSKeyedArchiver class])
	{
		Class unarchiverClass = (archiverClass == [NSKeyedArchiver class]) ? [NSKeyedUnarchiver class] : [NSUnarchiver class];
		
		NSData* archivedData = [archiverClass archivedDataWithRootObject:copiedObject];
		RMModelObjectTest* unarchivedObject = [unarchiverClass unarchiveObjectWithData:archivedData];
		
		STAssertNotNil(unarchivedObject, nil);
		
		STAssertEquals(unarchivedObject.i, 69, nil);
		STAssertEquals(unarchivedObject.b, YES, nil);
		STAssertEquals(unarchivedObject.ull, 18446744073709551610ULL, nil);
		
		STAssertFalse(unarchivedObject.assignedString == fooString, nil);
		if([NSGarbageCollector defaultCollector]) STAssertEqualObjects(unarchivedObject.assignedString, fooString, nil);
		
		STAssertFalse(unarchivedObject.retainedString == barString, nil);
		STAssertEqualObjects(unarchivedObject.retainedString, barString, nil);
		
		STAssertFalse(unarchivedObject.copiedString == bazString, nil);
		STAssertEqualObjects(unarchivedObject.copiedString, bazString, nil);
		STAssertEqualObjects(unarchivedObject.copiedString, testObject.copiedString, nil);
		STAssertEqualObjects(unarchivedObject.copiedString, copiedObject.copiedString, nil);
	}
	
	//
	
	copiedObject.assignedString = nil;
	STAssertEquals(copiedObject.assignedString, (id)nil, nil);
	STAssertNotNil(testObject.assignedString, nil);
	
	copiedObject.retainedString = nil;
	STAssertEquals(copiedObject.retainedString, (id)nil, nil);
	STAssertNotNil(testObject.retainedString, nil);
	
	copiedObject.copiedString = nil;
	STAssertEquals(copiedObject.copiedString, (id)nil, nil);
	STAssertNotNil(testObject.copiedString, nil);
	
	//
	
	[fooString release];
	[fooStringId release];
	[barString release];
	[bazString release];

	//
	
	[pool drain];
}

@end

//***************************************************************************
