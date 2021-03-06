/*
 * parser.j
 *
 * Created by Francisco Tolmasky.
 * Modified by Antoine Mercadal, with great help of Martin Carlberg
 * Copyright 2008-2013, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

@import <Foundation/Foundation.j>

var FILE = require("file");

// Debug function to print some JS objects
function dump(obj)
{
    CPLogPrint(JSON.stringify(obj));
}

var xcc = ObjectiveJ.acorn.walk.make(
    {
        ClassDeclarationStatement: function(node, st, c)
        {
            if (node.categoryname)
            {
                CPLogPrint("Categories are not supported yet. Ignoring it.");
                return;
            }

            var className = node.classname.name,
                superclassname = node.superclassname.name,
                declaredOutletsName = [],
                classInfo = {
                        "name": className,
                        "superClass": superclassname,
                        "outlets": [],
                        "actions": [],
                        "actionNames": []
                    };

            if (node.ivardeclarations)
            {
                for (var i = 0; i < node.ivardeclarations.length; ++i)
                {
                    var ivarDecl = node.ivardeclarations[i],
                        ivarType = ivarDecl.ivartype ? ivarDecl.ivartype.name : null,
                        ivarName = ivarDecl.id.name,
                        ivarHasOutlet = ivarDecl.outlet ? "@outlet" : null;

                    if (ivarHasOutlet)
                    {
                        if (declaredOutletsName.indexOf(ivarName) !== -1)
                            throw("Outlet named '" + ivarName + "' is declared multiple times.");

                        declaredOutletsName.push(ivarName);
                        classInfo.outlets.push({"type": ivarType, "name": ivarName});
                    }
                }
            }

            st.push(classInfo)

            for (var i = 0; i < node.body.length; ++i)
                c(node.body[i], classInfo, "Statement");
        },

        MethodDeclarationStatement: function(node, st, c)
        {
            var selectors = node.selectors,
                arguments = node.arguments,
                methodReturnType = [node.returntype ? node.returntype.name : "id"],
                methodHasAction = node.action ? "IBAction" : null,
                selector = selectors[0].name,
                actionInformations = {"name": selector, "arguments":[]};

            if (methodHasAction && arguments.length == 1)
            {
                if (st.actionNames.indexOf(selector) !== -1)
                    throw("Action named '" + selector + "' is declared multiple times.");

                st.actionNames.push(selector);

                for (var i = 0; i < arguments.length; i++)
                {
                    var argument = arguments[i],
                        argumentName = argument.identifier.name,
                        argumentType = argument.type ? argument.type.name : null;

                    actionInformations.arguments.push({"type": argumentType, "name": argumentName});
                }

                st.actions.push(actionInformations)
            }
            else if (methodHasAction)
                throw("Method '" + selector + "' is an action but has more than one parameter.");

        }
    }
);

function compile(node, state, visitor)
{
    function c(node, st, override)
    {
        visitor[override || node.type](node, st, c);
    }

    c(node, state);
};


function main(args)
{
    var fileURL = new CFURL(args[1]),
        outputHeaderURL = new CFURL(args[2]),
        outputSourceURL = new CFURL(args[3]),
        source = FILE.read(fileURL, { charset: "UTF-8" }),
        flags = ObjectiveJ.Preprocessor.Flags.IncludeDebugSymbols | ObjectiveJ.Preprocessor.Flags.IncludeTypeSignatures,
        tokens = ObjectiveJ.acorn.parse(source),
        classesInformation = [],
        ObjectiveCSource = "",
        ObjectiveCHeader = "";


    compile(tokens, classesInformation, xcc);

    // dump(classesInformation)

    ObjectiveCHeader +=
        "#import <Foundation/Foundation.h>\n" +
        "#import <Cocoa/Cocoa.h>\n" +
        "#import \"xcc_general_include.h\"\n\n";

    ObjectiveCSource += "#import \"" + outputHeaderURL.absoluteString().replace(/\\/g,'/').replace(/(.*\/)/g, '') + "\"\n\n";

    // Traverse each found classes
    classesInformation.forEach(function(aClass)
    {
        // add new class definition
        ObjectiveCHeader += "@interface " + aClass.name + " : " + NSCompatibleClassName(aClass.superClass) + "\n\n";

        // Add each outlets in header
        aClass.outlets.forEach(function(anOutlet)
        {
            ObjectiveCHeader += "@property (assign) IBOutlet " + NSCompatibleClassName(anOutlet.type, YES) + " " + anOutlet.name + ";\n";
        });

        ObjectiveCHeader += "\n";

        // Add each actions in header
        aClass.actions.forEach(function(anAction)
        {
            ObjectiveCHeader += "- (IBAction)" + anAction.name + ":(" + anAction.arguments[0].type + ")" + anAction.arguments[0].name + ";\n";
        });

        ObjectiveCHeader += "\n@end\n\n\n";

        // fill up the implementation file
        ObjectiveCSource += "@implementation " + aClass.name + "\n@end\n\n";
    });

    // write files
   if (ObjectiveCSource.length)
       FILE.write(outputSourceURL, ObjectiveCSource, { charset:"UTF-8" });

   if (ObjectiveCHeader.length)
       FILE.write(outputHeaderURL, ObjectiveCHeader, { charset:"UTF-8" });
}

function NSCompatibleClassName(aClassName, asPointer)
{
   if (aClassName === "var" || aClassName === "id")
       return "id";

   var prefix = aClassName.substr(0, 2),
       asterisk = asPointer ? "*" : "";

   if (prefix !== "CP")
       return aClassName + asterisk;

   var NSClassName = "NS" + aClassName.substr(2);

   if (NSClasses[NSClassName])
       return NSClassName + asterisk;

   if (ReplacementClasses[aClassName])
       return ReplacementClasses[aClassName] + asterisk;

   return aClassName + asterisk;
}

var ReplacementClasses = {
        "CPWebView": "WebView"
    };

var NSClasses = {
                   "NSAffineTransform" : YES,
                   "NSAppleEventDescriptor" : YES,
                   "NSAppleEventManager" : YES,
                   "NSAppleScript" : YES,
                   "NSArchiver" : YES,
                   "NSArray" : YES,
                   "NSAssertionHandler" : YES,
                   "NSAttributedString" : YES,
                   "NSAutoreleasePool" : YES,
                   "NSBlockOperation" : YES,
                   "NSBundle" : YES,
                   "NSCache" : YES,
                   "NSCachedURLResponse" : YES,
                   "NSCalendar" : YES,
                   "NSCharacterSet" : YES,
                   "NSClassDescription" : YES,
                   "NSCloneCommand" : YES,
                   "NSCloseCommand" : YES,
                   "NSCoder" : YES,
                   "NSComparisonPredicate" : YES,
                   "NSCompoundPredicate" : YES,
                   "NSCondition" : YES,
                   "NSConditionLock" : YES,
                   "NSConnection" : YES,
                   "NSCountCommand" : YES,
                   "NSCountedSet" : YES,
                   "NSCreateCommand" : YES,
                   "NSData" : YES,
                   "NSDate" : YES,
                   "NSDateComponents" : YES,
                   "NSDateFormatter" : YES,
                   "NSDecimalNumber" : YES,
                   "NSDecimalNumberHandler" : YES,
                   "NSDeleteCommand" : YES,
                   "NSDeserializer" : YES,
                   "NSDictionary" : YES,
                   "NSDirectoryEnumerator" : YES,
                   "NSDistantObject" : YES,
                   "NSDistantObjectRequest" : YES,
                   "NSDistributedLock" : YES,
                   "NSDistributedNotificationCenter" : YES,
                   "NSEnumerator" : YES,
                   "NSError" : YES,
                   "NSException" : YES,
                   "NSExistsCommand" : YES,
                   "NSExpression" : YES,
                   "NSFileHandle" : YES,
                   "NSFileManager" : YES,
                   "NSFileWrapper" : YES,
                   "NSFormatter" : YES,
                   "NSGarbageCollector" : YES,
                   "NSGetCommand" : YES,
                   "NSHashTable" : YES,
                   "NSHost" : YES,
                   "NSHTTPCookie" : YES,
                   "NSHTTPCookieStorage" : YES,
                   "NSHTTPURLResponse" : YES,
                   "NSIndexPath" : YES,
                   "NSIndexSet" : YES,
                   "NSIndexSpecifier" : YES,
                   "NSInputStream" : YES,
                   "NSInvocation" : YES,
                   "NSInvocationOperation" : YES,
                   "NSKeyedArchiver" : YES,
                   "NSKeyedUnarchiver" : YES,
                   "NSLocale" : YES,
                   "NSLock" : YES,
                   "NSLogicalTest" : YES,
                   "NSMachBootstrapServer" : YES,
                   "NSMachPort" : YES,
                   "NSMapTable" : YES,
                   "NSMessagePort" : YES,
                   "NSMessagePortNameServer" : YES,
                   "NSMetadataItem" : YES,
                   "NSMetadataQuery" : YES,
                   "NSMetadataQueryAttributeValueTuple" : YES,
                   "NSMetadataQueryResultGroup" : YES,
                   "NSMethodSignature" : YES,
                   "NSMiddleSpecifier" : YES,
                   "NSMoveCommand" : YES,
                   "NSMutableArray" : YES,
                   "NSMutableAttributedString" : YES,
                   "NSMutableCharacterSet" : YES,
                   "NSMutableData" : YES,
                   "NSMutableDictionary" : YES,
                   "NSMutableIndexSet" : YES,
                   "NSMutableSet" : YES,
                   "NSMutableString" : YES,
                   "NSMutableURLRequest" : YES,
                   "NSNameSpecifier" : YES,
                   "NSNetService" : YES,
                   "NSNetServiceBrowser" : YES,
                   "NSNotification" : YES,
                   "NSNotificationCenter" : YES,
                   "NSNotificationQueue" : YES,
                   "NSNull" : YES,
                   "NSNumber" : YES,
                   "NSNumberFormatter" : YES,
                   "NSObject" : YES,
                   "NSOperation" : YES,
                   "NSOperationQueue" : YES,
                   "NSOrthography" : YES,
                   "NSOutputStream" : YES,
                   "NSPipe" : YES,
                   "NSPointerArray" : YES,
                   "NSPointerFunctions" : YES,
                   "NSPort" : YES,
                   "NSPortCoder" : YES,
                   "NSPortMessage" : YES,
                   "NSPortNameServer" : YES,
                   "NSPositionalSpecifier" : YES,
                   "NSPredicate" : YES,
                   "NSProcessInfo" : YES,
                   "NSPropertyListSerialization" : YES,
                   "NSPropertySpecifier" : YES,
                   "NSProtocolChecker" : YES,
                   "NSProxy" : YES,
                   "NSPurgeableData" : YES,
                   "NSQuitCommand" : YES,
                   "NSRandomSpecifier" : YES,
                   "NSRangeSpecifier" : YES,
                   "NSRecursiveLock" : YES,
                   "NSRelativeSpecifier" : YES,
                   "NSRunLoop" : YES,
                   "NSScanner" : YES,
                   "NSScriptClassDescription" : YES,
                   "NSScriptCoercionHandler" : YES,
                   "NSScriptCommand" : YES,
                   "NSScriptCommandDescription" : YES,
                   "NSScriptExecutionContext" : YES,
                   "NSScriptObjectSpecifier" : YES,
                   "NSScriptSuiteRegistry" : YES,
                   "NSScriptWhoseTest" : YES,
                   "NSSerializer" : YES,
                   "NSSet" : YES,
                   "NSSetCommand" : YES,
                   "NSSocketPort" : YES,
                   "NSSocketPortNameServer" : YES,
                   "NSSortDescriptor" : YES,
                   "NSSpecifierTest" : YES,
                   "NSSpellServer" : YES,
                   "NSStream" : YES,
                   "NSString" : YES,
                   "NSTask" : YES,
                   "NSTextCheckingResult" : YES,
                   "NSThread" : YES,
                   "NSTimer" : YES,
                   "NSTimeZone" : YES,
                   "NSUnarchiver" : YES,
                   "NSUndoManager" : YES,
                   "NSUniqueIDSpecifier" : YES,
                   "NSURL" : YES,
                   "NSURLAuthenticationChallenge" : YES,
                   "NSURLCache" : YES,
                   "NSURLConnection" : YES,
                   "NSURLCredential" : YES,
                   "NSURLCredentialStorage" : YES,
                   "NSURLDownload" : YES,
                   "NSURLHandle" : YES,
                   "NSURLProtectionSpace" : YES,
                   "NSURLProtocol" : YES,
                   "NSURLRequest" : YES,
                   "NSURLResponse" : YES,
                   "NSUserDefaults" : YES,
                   "NSValue" : YES,
                   "NSValueTransformer" : YES,
                   "NSWhoseSpecifier" : YES,
                   "NSXMLDocument" : YES,
                   "NSXMLDTD" : YES,
                   "NSXMLDTDNode" : YES,
                   "NSXMLElement" : YES,
                   "NSXMLNode" : YES,
                   "NSXMLParser" : YES,
                                       "NSActionCell" : YES,
                   "NSAffineTransform Additions" : YES,
                   "NSAlert" : YES,
                   "NSAnimation" : YES,
                   "NSAnimationContext" : YES,
                   "NSAppleScript Additions" : YES,
                   "NSApplication" : YES,
                   "NSArrayController" : YES,
                   "NSATSTypesetter" : YES,
                   "NSAttributedString Application Kit Additions" : YES,
                   "NSBezierPath" : YES,
                   "NSBitmapImageRep" : YES,
                   "NSBox" : YES,
                   "NSBrowser" : YES,
                   "NSBrowserCell" : YES,
                   "NSBundle Additions" : YES,
                   "NSButton" : YES,
                   "NSButtonCell" : YES,
                   "NSCachedImageRep" : YES,
                   "NSCell" : YES,
                   "NSCIImageRep" : YES,
                   "NSClipView" : YES,
                   "NSCoder Application Kit Additions" : YES,
                   "NSCollectionView" : YES,
                   "NSCollectionViewItem" : YES,
                   "NSColor" : YES,
                   "NSColorList" : YES,
                   "NSColorPanel" : YES,
                   "NSColorPicker" : YES,
                   "NSColorSpace" : YES,
                   "NSColorWell" : YES,
                   "NSComboBox" : YES,
                   "NSComboBoxCell" : YES,
                   "NSControl" : YES,
                   "NSController" : YES,
                   "NSCursor" : YES,
                   "NSCustomImageRep" : YES,
                   "NSDatePicker" : YES,
                   "NSDatePickerCell" : YES,
                   "NSDictionaryController" : YES,
                   "NSDockTile" : YES,
                   "NSDocument" : YES,
                   "NSDocumentController" : YES,
                   "NSDrawer" : YES,
                   "NSEPSImageRep" : YES,
                   "NSEvent" : YES,
                   "NSFileWrapper" : YES,
                   "NSFont" : YES,
                   "NSFontDescriptor" : YES,
                   "NSFontManager" : YES,
                   "NSFontPanel" : YES,
                   "NSForm" : YES,
                   "NSFormCell" : YES,
                   "NSGlyphGenerator" : YES,
                   "NSGlyphInfo" : YES,
                   "NSGradient" : YES,
                   "NSGraphicsContext" : YES,
                   "NSHelpManager" : YES,
                   "NSImage" : YES,
                   "NSImageCell" : YES,
                   "NSImageRep" : YES,
                   "NSImageView" : YES,
                   "NSLayoutManager" : YES,
                   "NSLevelIndicator" : YES,
                   "NSLevelIndicatorCell" : YES,
                   "NSMatrix" : YES,
                   "NSMenu" : YES,
                   "NSMenuItem" : YES,
                   "NSMenuItemCell" : YES,
                   "NSMenuView" : YES,
                   "NSMutableAttributedString Additions" : YES,
                   "NSMutableParagraphStyle" : YES,
                   "NSNib" : YES,
                   "NSNibConnector" : YES,
                   "NSNibControlConnector" : YES,
                   "NSNibOutletConnector" : YES,
                   "NSObjectController" : YES,
                   "NSOpenGLContext" : YES,
                   "NSOpenGLLayer" : YES,
                   "NSOpenGLPixelBuffer" : YES,
                   "NSOpenGLPixelFormat" : YES,
                   "NSOpenGLView" : YES,
                   "NSOpenPanel" : YES,
                   "NSOutlineView" : YES,
                   "NSPageLayout" : YES,
                   "NSPanel" : YES,
                   "NSParagraphStyle" : YES,
                   "NSPasteboard" : YES,
                   "NSPasteboardItem" : YES,
                   "NSPathCell" : YES,
                   "NSPathComponentCell" : YES,
                   "NSPathControl" : YES,
                   "NSPDFImageRep" : YES,
                   "NSPersistentDocument" : YES,
                   "NSPICTImageRep" : YES,
                   "NSPopUpButton" : YES,
                   "NSPopUpButtonCell" : YES,
                   "NSPredicateEditor" : YES,
                   "NSPredicateEditorRowTemplate" : YES,
                   "NSPrinter" : YES,
                   "NSPrintInfo" : YES,
                   "NSPrintOperation" : YES,
                   "NSPrintPanel" : YES,
                   "NSProgressIndicator" : YES,
                   "NSResponder" : YES,
                   "NSRuleEditor" : YES,
                   "NSRulerMarker" : YES,
                   "NSRulerView" : YES,
                   "NSRunningApplication" : YES,
                   "NSSavePanel" : YES,
                   "NSScreen" : YES,
                   "NSScroller" : YES,
                   "NSScrollView" : YES,
                   "NSSearchField" : YES,
                   "NSSearchFieldCell" : YES,
                   "NSSecureTextField" : YES,
                   "NSSecureTextFieldCell" : YES,
                   "NSSegmentedCell" : YES,
                   "NSSegmentedControl" : YES,
                   "NSShadow" : YES,
                   "NSSlider" : YES,
                   "NSSliderCell" : YES,
                   "NSSound" : YES,
                   "NSSpeechRecognizer" : YES,
                   "NSSpeechSynthesizer" : YES,
                   "NSSpellChecker" : YES,
                   "NSSplitView" : YES,
                   "NSStatusBar" : YES,
                   "NSStatusItem" : YES,
                   "NSStepper" : YES,
                   "NSStepperCell" : YES,
                   "NSString Application Kit Additions" : YES,
                   "NSTableColumn" : YES,
                   "NSTableHeaderCell" : YES,
                   "NSTableHeaderView" : YES,
                   "NSTableView" : YES,
                   "NSTabView" : YES,
                   "NSTabViewItem" : YES,
                   "NSText" : YES,
                   "NSTextAttachment" : YES,
                   "NSTextAttachmentCell" : YES,
                   "NSTextBlock" : YES,
                   "NSTextContainer" : YES,
                   "NSTextField" : YES,
                   "NSTextFieldCell" : YES,
                   "NSTextInputContext" : YES,
                   "NSTextList" : YES,
                   "NSTextStorage" : YES,
                   "NSTextTab" : YES,
                   "NSTextTable" : YES,
                   "NSTextTableBlock" : YES,
                   "NSTextView" : YES,
                   "NSTokenField" : YES,
                   "NSTokenFieldCell" : YES,
                   "NSToolbar" : YES,
                   "NSToolbarItem" : YES,
                   "NSToolbarItemGroup" : YES,
                   "NSTouch" : YES,
                   "NSTrackingArea" : YES,
                   "NSTreeController" : YES,
                   "NSTreeNode" : YES,
                   "NSTypesetter" : YES,
                   "NSURL Additions" : YES,
                   "NSUserDefaultsController" : YES,
                   "NSView" : YES,
                   "NSViewAnimation" : YES,
                   "NSViewController" : YES,
                   "NSWindow" : YES,
                   "NSWindowController" : YES,
                   "NSWorkspace" : YES,
                   "NSPopover": YES
               };
