////////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import XCTest
#if DEBUG
    @testable import RealmSwift
#else
    import RealmSwift
#endif
import Foundation

#if swift(>=3.0)

class RealmTests: TestCase {
    func testFileURL() {
        XCTAssertEqual(try! Realm(fileURL: testRealmURL()).configuration.fileURL,
                       testRealmURL())
    }

    func testReadOnly() {
        autoreleasepool {
            XCTAssertEqual(try! Realm().configuration.readOnly, false)

            try! Realm().write {
                try! Realm().createObject(ofType: SwiftIntObject.self, populatedWith: [100])
            }
        }
        let config = Realm.Configuration(fileURL: defaultRealmURL(), readOnly: true)
        let readOnlyRealm = try! Realm(configuration: config)
        XCTAssertEqual(true, readOnlyRealm.configuration.readOnly)
        XCTAssertEqual(1, readOnlyRealm.allObjects(ofType: SwiftIntObject.self).count)

        assertThrows(try! Realm(), "Realm has different readOnly settings")
    }

    func testOpeningInvalidPathThrows() {
        assertFails(Error.FileAccess) {
            try Realm(configuration: Realm.Configuration(fileURL: URL(fileURLWithPath: "/dev/null/foo")))
        }
    }

    func testReadOnlyFile() {
        autoreleasepool {
            let realm = try! Realm(fileURL: testRealmURL())
            try! realm.write {
                realm.createObject(ofType: SwiftStringObject.self, populatedWith: ["a"])
            }
        }

        let fileManager = FileManager.default()
        try! fileManager.setAttributes([ FileAttributeKey.immutable.rawValue: true ], ofItemAtPath: testRealmURL().path!)

        // Should not be able to open read-write
        assertFails(Error.FileAccess) {
            try Realm(fileURL: testRealmURL())
        }

        assertSucceeds {
            let realm = try Realm(configuration:
                Realm.Configuration(fileURL: testRealmURL(), readOnly: true))
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftStringObject.self).count)
        }

        try! fileManager.setAttributes([ FileAttributeKey.immutable.rawValue: false ], ofItemAtPath: testRealmURL().path!)
    }

    func testReadOnlyRealmMustExist() {
        assertFails(Error.FileNotFound) {
            try Realm(configuration:
                Realm.Configuration(fileURL: defaultRealmURL(), readOnly: true))
        }
    }

    func testFilePermissionDenied() {
        autoreleasepool {
            let _ = try! Realm(fileURL: testRealmURL())
        }

        // Make Realm at test path temporarily unreadable
        let fileManager = FileManager.default()
        let permissions = try! fileManager
            .attributesOfItem(atPath: testRealmURL().path!)[FileAttributeKey.posixPermissions.rawValue] as! NSNumber
        try! fileManager.setAttributes([ FileAttributeKey.posixPermissions.rawValue: 0000 ],
                                       ofItemAtPath: testRealmURL().path!)

        assertFails(Error.FilePermissionDenied) {
            try Realm(fileURL: testRealmURL())
        }

        try! fileManager.setAttributes([FileAttributeKey.posixPermissions.rawValue: permissions], ofItemAtPath: testRealmURL().path!)
    }

    #if DEBUG
    func testFileFormatUpgradeRequiredButDisabled() {
        var config = Realm.Configuration()
        var bundledRealmPath = NSBundle(forClass: RealmTests.self).pathForResource("fileformat-pre-null.realm",
                                                                                   ofType: nil)!
        try! NSFileManager.defaultManager.copyItemAtPath(bundledRealmPath, toPath: config.path)
        config.disableFormatUpgrade = true
        assertFails(Error.FileFormatUpgradeRequired) {
            try Realm(configuration: config)
        }
    }
    #endif

    func testSchema() {
        let schema = try! Realm().schema
        XCTAssert(schema as AnyObject is Schema)
        XCTAssertEqual(1, schema.objectSchema.filter({ $0.className == "SwiftStringObject" }).count)
    }

    func testIsEmpty() {
        let realm = try! Realm()
        XCTAssert(realm.isEmpty, "Realm should be empty on creation.")

        realm.beginWrite()
        realm.createObject(ofType: SwiftStringObject.self, populatedWith: ["a"])
        XCTAssertFalse(realm.isEmpty, "Realm should not be empty within a write transaction after adding an object.")
        realm.cancelWrite()

        XCTAssertTrue(realm.isEmpty, "Realm should be empty after canceling a write transaction that added an object.")

        realm.beginWrite()
        realm.createObject(ofType: SwiftStringObject.self, populatedWith: ["a"])
        try! realm.commitWrite()
        XCTAssertFalse(realm.isEmpty,
            "Realm should not be empty after committing a write transaction that added an object.")
    }

    func testInit() {
        XCTAssertEqual(try! Realm(fileURL: testRealmURL()).configuration.fileURL,
                       testRealmURL())
    }

    func testInitFailable() {
        autoreleasepool {
            _ = try! Realm()
        }

        FileManager.default().createFile(atPath: defaultRealmURL().path!,
            contents:"a".data(using: String.Encoding.utf8, allowLossyConversion: false),
            attributes: nil)

        assertFails(Error.FileAccess) {
            _ = try Realm()
            XCTFail("Realm creation should have failed")
        }
    }

    func testInitInMemory() {
        autoreleasepool {
            let realm = inMemoryRealm("identifier")
            try! realm.write {
                realm.createObject(ofType: SwiftIntObject.self, populatedWith: [1])
                return
            }
        }
        let realm = inMemoryRealm("identifier")
        XCTAssertEqual(realm.allObjects(ofType: SwiftIntObject.self).count, 0)

        try! realm.write {
            realm.createObject(ofType: SwiftIntObject.self, populatedWith: [1])
            XCTAssertEqual(realm.allObjects(ofType: SwiftIntObject.self).count, 1)

            inMemoryRealm("identifier").createObject(ofType: SwiftIntObject.self, populatedWith: [1])
            XCTAssertEqual(realm.allObjects(ofType: SwiftIntObject.self).count, 2)
        }

        let realm2 = inMemoryRealm("identifier2")
        XCTAssertEqual(realm2.allObjects(ofType: SwiftIntObject.self).count, 0)
    }

    func testInitCustomClassList() {
        let configuration = Realm.Configuration(fileURL: Realm.Configuration.defaultConfiguration.fileURL,
            objectTypes: [SwiftStringObject.self])
        XCTAssert(configuration.objectTypes! is [SwiftStringObject.Type])
        let realm = try! Realm(configuration: configuration)
        XCTAssertEqual(["SwiftStringObject"], realm.schema.objectSchema.map { $0.className })
    }

    func testWrite() {
        try! Realm().write {
            self.assertThrows(try! Realm().beginWrite())
            self.assertThrows(try! Realm().write { })
            try! Realm().createObject(ofType: SwiftStringObject.self, populatedWith: ["1"])
            XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 1)
        }
        XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 1)
    }

    func testDynamicWrite() {
        try! Realm().write {
            self.assertThrows(try! Realm().beginWrite())
            self.assertThrows(try! Realm().write { })
            try! Realm().createDynamicObject(ofType: "SwiftStringObject", populatedWith: ["1"])
            XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 1)
        }
        XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 1)
    }

    func testDynamicWriteSubscripting() {
        try! Realm().beginWrite()
        let object = try! Realm().createDynamicObject(ofType: "SwiftStringObject", populatedWith: ["1"])
        try! Realm().commitWrite()

        XCTAssertNotNil(object, "Dynamic Object Creation Failed")

        let stringVal = object["stringCol"] as! String
        XCTAssertEqual(stringVal, "1", "Object Subscripting Failed")
    }

    func testBeginWrite() {
        try! Realm().beginWrite()
        assertThrows(try! Realm().beginWrite())
        try! Realm().cancelWrite()
        try! Realm().beginWrite()
        try! Realm().createObject(ofType: SwiftStringObject.self, populatedWith: ["1"])
        XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 1)
    }

    func testCommitWrite() {
        try! Realm().beginWrite()
        try! Realm().createObject(ofType: SwiftStringObject.self, populatedWith: ["1"])
        try! Realm().commitWrite()
        XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 1)
        try! Realm().beginWrite()
    }

    func testCancelWrite() {
        assertThrows(try! Realm().cancelWrite())
        try! Realm().beginWrite()
        try! Realm().createObject(ofType: SwiftStringObject.self, populatedWith: ["1"])
        try! Realm().cancelWrite()
        XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 0)

        try! Realm().write {
            self.assertThrows(self.realmWithTestPath().cancelWrite())
            let object = try! Realm().createObject(ofType: SwiftStringObject.self)
            try! Realm().cancelWrite()
            XCTAssertTrue(object.isInvalidated)
            XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 0)
        }
        XCTAssertEqual(try! Realm().allObjects(ofType: SwiftStringObject.self).count, 0)
    }

    func testInWriteTransaction() {
        let realm = try! Realm()
        XCTAssertFalse(realm.isInWriteTransaction)
        realm.beginWrite()
        XCTAssertTrue(realm.isInWriteTransaction)
        realm.cancelWrite()
        try! realm.write {
            XCTAssertTrue(realm.isInWriteTransaction)
            realm.cancelWrite()
            XCTAssertFalse(realm.isInWriteTransaction)
        }

        realm.beginWrite()
        realm.invalidate()
        XCTAssertFalse(realm.isInWriteTransaction)
    }

    func testAddSingleObject() {
        let realm = try! Realm()
        assertThrows(_ = realm.add(SwiftObject()))
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
        var defaultRealmObject: SwiftObject!
        try! realm.write {
            defaultRealmObject = SwiftObject()
            realm.add(defaultRealmObject)
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftObject.self).count)
            realm.add(defaultRealmObject)
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftObject.self).count)
        }
        XCTAssertEqual(1, realm.allObjects(ofType: SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(defaultRealmObject))
        }
    }

    func testAddWithUpdateSingleObject() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftPrimaryStringObject.self).count)
        var defaultRealmObject: SwiftPrimaryStringObject!
        try! realm.write {
            defaultRealmObject = SwiftPrimaryStringObject()
            realm.add(defaultRealmObject, update: true)
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftPrimaryStringObject.self).count)
            realm.add(SwiftPrimaryStringObject(), update: true)
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftPrimaryStringObject.self).count)
        }
        XCTAssertEqual(1, realm.allObjects(ofType: SwiftPrimaryStringObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(defaultRealmObject, update: true))
        }
    }

    func testAddMultipleObjects() {
        let realm = try! Realm()
        assertThrows(_ = realm.add([SwiftObject(), SwiftObject()]))
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
        try! realm.write {
            let objs = [SwiftObject(), SwiftObject()]
            realm.add(objs)
            XCTAssertEqual(2, realm.allObjects(ofType: SwiftObject.self).count)
        }
        XCTAssertEqual(2, realm.allObjects(ofType: SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(realm.allObjects(ofType: SwiftObject.self)))
        }
    }

    func testAddWithUpdateMultipleObjects() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftPrimaryStringObject.self).count)
        try! realm.write {
            let objs = [SwiftPrimaryStringObject(), SwiftPrimaryStringObject()]
            realm.add(objs, update: true)
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftPrimaryStringObject.self).count)
        }
        XCTAssertEqual(1, realm.allObjects(ofType: SwiftPrimaryStringObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(realm.allObjects(ofType: SwiftPrimaryStringObject.self), update: true))
        }
    }

    // create() tests are in ObjectCreationTests.swift

    func testDeleteSingleObject() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
        assertThrows(_ = realm.delete(SwiftObject()))
        var defaultRealmObject: SwiftObject!
        try! realm.write {
            defaultRealmObject = SwiftObject()
            self.assertThrows(_ = realm.delete(defaultRealmObject))
            XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
            realm.add(defaultRealmObject)
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftObject.self).count)
            realm.delete(defaultRealmObject)
            XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
        }
        assertThrows(_ = realm.delete(defaultRealmObject))
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        assertThrows(_ = testRealm.delete(defaultRealmObject))
        try! testRealm.write {
            self.assertThrows(_ = testRealm.delete(defaultRealmObject))
        }
    }

    func testDeleteSequenceOfObjects() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
        var objs: [SwiftObject]!
        try! realm.write {
            objs = [SwiftObject(), SwiftObject()]
            realm.add(objs)
            XCTAssertEqual(2, realm.allObjects(ofType: SwiftObject.self).count)
            realm.delete(objs)
            XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
        }
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        assertThrows(_ = testRealm.delete(objs))
        try! testRealm.write {
            self.assertThrows(_ = testRealm.delete(objs))
        }
    }

    func testDeleteListOfObjects() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftCompanyObject.self).count)
        try! realm.write {
            let obj = SwiftCompanyObject()
            obj.employees.append(SwiftEmployeeObject())
            realm.add(obj)
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftEmployeeObject.self).count)
            realm.delete(obj.employees)
            XCTAssertEqual(0, obj.employees.count)
            XCTAssertEqual(0, realm.allObjects(ofType: SwiftEmployeeObject.self).count)
        }
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftEmployeeObject.self).count)
    }

    func testDeleteResults() {
        let realm = try! Realm(fileURL: testRealmURL())
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftCompanyObject.self).count)
        try! realm.write {
            realm.add(SwiftIntObject(value: [1]))
            realm.add(SwiftIntObject(value: [1]))
            realm.add(SwiftIntObject(value: [2]))
            XCTAssertEqual(3, realm.allObjects(ofType: SwiftIntObject.self).count)
            realm.delete(realm.allObjects(ofType: SwiftIntObject.self).filter(using: "intCol = 1"))
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftIntObject.self).count)
        }
        XCTAssertEqual(1, realm.allObjects(ofType: SwiftIntObject.self).count)
    }

    func testDeleteAll() {
        let realm = try! Realm()
        try! realm.write {
            realm.add(SwiftObject())
            XCTAssertEqual(1, realm.allObjects(ofType: SwiftObject.self).count)
            realm.deleteAllObjects()
            XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
        }
        XCTAssertEqual(0, realm.allObjects(ofType: SwiftObject.self).count)
    }

    func testObjects() {
        try! Realm().write {
            try! Realm().createObject(ofType: SwiftIntObject.self, populatedWith: [100])
            try! Realm().createObject(ofType: SwiftIntObject.self, populatedWith: [200])
            try! Realm().createObject(ofType: SwiftIntObject.self, populatedWith: [300])
        }

        XCTAssertEqual(0, try! Realm().allObjects(ofType: SwiftStringObject.self).count)
        XCTAssertEqual(3, try! Realm().allObjects(ofType: SwiftIntObject.self).count)
        assertThrows(try! Realm().allObjects(ofType: Object.self))
    }

    func testDynamicObjects() {
        try! Realm().write {
            try! Realm().createObject(ofType: SwiftIntObject.self, populatedWith: [100])
            try! Realm().createObject(ofType: SwiftIntObject.self, populatedWith: [200])
            try! Realm().createObject(ofType: SwiftIntObject.self, populatedWith: [300])
        }

        XCTAssertEqual(0, try! Realm().allDynamicObjects(ofType: "SwiftStringObject").count)
        XCTAssertEqual(3, try! Realm().allDynamicObjects(ofType: "SwiftIntObject").count)
        assertThrows(try! Realm().allDynamicObjects(ofType: "Object"))
    }

    func testDynamicObjectProperties() {
        try! Realm().write {
            try! Realm().createObject(ofType: SwiftObject.self)
        }

        let object = try! Realm().allDynamicObjects(ofType: "SwiftObject")[0]
        let dictionary = SwiftObject.defaultValues()

        XCTAssertEqual(object["boolCol"] as? NSNumber, dictionary["boolCol"] as! NSNumber?)
        XCTAssertEqual(object["intCol"] as? NSNumber, dictionary["intCol"] as! NSNumber?)
        XCTAssertEqualWithAccuracy(object["floatCol"] as! Float, dictionary["floatCol"] as! Float, accuracy: 0.001)
        XCTAssertEqual(object["doubleCol"] as? NSNumber, dictionary["doubleCol"] as! NSNumber?)
        XCTAssertEqual(object["stringCol"] as! String?, dictionary["stringCol"] as! String?)
        XCTAssertEqual(object["binaryCol"] as! NSData?, dictionary["binaryCol"] as! NSData?)
        XCTAssertEqual(object["dateCol"] as! NSDate?, dictionary["dateCol"] as! NSDate?)
        XCTAssertEqual(object["objectCol"]?.boolCol, false)
    }

    func testDynamicObjectOptionalProperties() {
        try! Realm().write {
            try! Realm().createObject(ofType: SwiftOptionalDefaultValuesObject.self)
        }

        let object = try! Realm().allDynamicObjects(ofType: "SwiftOptionalDefaultValuesObject")[0]
        let dictionary = SwiftOptionalDefaultValuesObject.defaultValues()

        XCTAssertEqual(object["optIntCol"] as? NSNumber, dictionary["optIntCol"] as! NSNumber?)
        XCTAssertEqual(object["optInt8Col"] as? NSNumber, dictionary["optInt8Col"] as! NSNumber?)
        XCTAssertEqual(object["optInt16Col"] as? NSNumber, dictionary["optInt16Col"] as! NSNumber?)
        XCTAssertEqual(object["optInt32Col"] as? NSNumber, dictionary["optInt32Col"] as! NSNumber?)
        XCTAssertEqual(object["optInt64Col"] as? NSNumber, dictionary["optInt64Col"] as! NSNumber?)
        XCTAssertEqual(object["optFloatCol"] as? NSNumber, dictionary["optFloatCol"] as! NSNumber?)
        XCTAssertEqual(object["optDoubleCol"] as? NSNumber, dictionary["optDoubleCol"] as! NSNumber?)
        XCTAssertEqual(object["optStringCol"] as! String?, dictionary["optStringCol"] as! String?)
        XCTAssertEqual(object["optNSStringCol"] as! String?, dictionary["optNSStringCol"] as! String?)
        XCTAssertEqual(object["optBinaryCol"] as! NSData?, dictionary["optBinaryCol"] as! NSData?)
        XCTAssertEqual(object["optDateCol"] as! NSDate?, dictionary["optDateCol"] as! NSDate?)
        XCTAssertEqual(object["optObjectCol"]?.boolCol, true)
    }

    func testObjectForPrimaryKey() {
        let intTypes: [Object.Type] = [SwiftPrimaryIntObject.self,
                                       SwiftPrimaryInt8Object.self,
                                       SwiftPrimaryInt16Object.self,
                                       SwiftPrimaryInt32Object.self,
                                       SwiftPrimaryInt64Object.self]
        let optionalIntTypes: [Object.Type] = [SwiftPrimaryOptionalIntObject.self,
                                               SwiftPrimaryOptionalInt8Object.self,
                                               SwiftPrimaryOptionalInt16Object.self,
                                               SwiftPrimaryOptionalInt32Object.self,
                                               SwiftPrimaryOptionalInt64Object.self]

        let realm = try! Realm()
        try! realm.write {
            realm.createObject(ofType: SwiftPrimaryStringObject.self, populatedWith: ["a", 1])
            realm.createObject(ofType: SwiftPrimaryStringObject.self, populatedWith: ["b", 2])

            realm.createObject(ofType: SwiftPrimaryOptionalStringObject.self, populatedWith: [NSNull(), 1])
            realm.createObject(ofType: SwiftPrimaryOptionalStringObject.self, populatedWith: ["b", 2])

            func createIntObject(_ objectType: Object.Type) {
                realm.createObject(ofType: objectType, populatedWith: ["a", 1])
                realm.createObject(ofType: objectType, populatedWith: ["b", 2])
            }

            func createOptionalIntObject(_ objectType: Object.Type) {
                realm.createObject(ofType: objectType, populatedWith: ["a", NSNull()])
                realm.createObject(ofType: objectType, populatedWith: ["b", 2])
            }

            for type in intTypes {
                createIntObject(type)
            }

            for type in optionalIntTypes {
                createOptionalIntObject(type)
            }
        }

        do {
            // When this is directly inside the XCTAssertNotNil, it doesn't work
            let object = realm.object(ofType: SwiftPrimaryStringObject.self, forPrimaryKey: "a")
            XCTAssertNotNil(object)

            // When this is directly inside the XCTAssertNil, it fails for some reason
            let missingObject = realm.object(ofType: SwiftPrimaryStringObject.self, forPrimaryKey: "z")
            XCTAssertNil(missingObject)
        }

        do {
            let object1 = realm.object(ofType: SwiftPrimaryOptionalStringObject.self, forPrimaryKey: NSNull())
            XCTAssertNotNil(object1)

            let object2 = realm.object(ofType: SwiftPrimaryOptionalStringObject.self, forPrimaryKey: "b")
            XCTAssertNotNil(object2)

            let missingObject = realm.object(ofType: SwiftPrimaryOptionalStringObject.self, forPrimaryKey: "z")
            XCTAssertNil(missingObject)
        }

        func assertIntObject(_ objectType: Object.Type) {
            let object = realm.object(ofType: objectType, forPrimaryKey: 1)
            XCTAssertNotNil(object)

            let missingObject = realm.object(ofType: objectType, forPrimaryKey: 0)
            XCTAssertNil(missingObject)
        }

        func assertOptionalIntObject(_ objectType: Object.Type) {
            let object1 = realm.object(ofType: objectType, forPrimaryKey: NSNull())
            XCTAssertNotNil(object1)

            let object2 = realm.object(ofType: objectType, forPrimaryKey: 2)
            XCTAssertNotNil(object2)

            let missingObject = realm.object(ofType: objectType, forPrimaryKey: 0)
            XCTAssertNil(missingObject)
        }

        for type in intTypes {
            assertIntObject(type)
        }

        for type in optionalIntTypes {
            assertOptionalIntObject(type)
        }
    }

    func testDynamicObjectForPrimaryKey() {
        let realm = try! Realm()
        try! realm.write {
            realm.createObject(ofType: SwiftPrimaryStringObject.self, populatedWith: ["a", 1])
            realm.createObject(ofType: SwiftPrimaryStringObject.self, populatedWith: ["b", 2])
        }

        XCTAssertNotNil(realm.dynamicObject(ofType: "SwiftPrimaryStringObject", forPrimaryKey: "a"))
        XCTAssertNil(realm.dynamicObject(ofType: "SwiftPrimaryStringObject", forPrimaryKey: "z"))
    }

    func testDynamicObjectForPrimaryKeySubscripting() {
        let realm = try! Realm()
        try! realm.write {
            realm.createObject(ofType: SwiftPrimaryStringObject.self, populatedWith: ["a", 1])
        }

        let object = realm.dynamicObject(ofType: "SwiftPrimaryStringObject", forPrimaryKey: "a")

        let stringVal = object!["stringCol"] as! String

        XCTAssertEqual(stringVal, "a", "Object Subscripting Failed!")
    }

    func testAddNotificationBlock() {
        let realm = try! Realm()
        var notificationCalled = false
        let token = realm.addNotificationBlock { _, realm in
            XCTAssertEqual(realm.configuration.fileURL, self.defaultRealmURL())
            notificationCalled = true
        }
        XCTAssertFalse(notificationCalled)
        try! realm.write {}
        XCTAssertTrue(notificationCalled)
        token.stop()
    }

    func testRemoveNotification() {
        let realm = try! Realm()
        var notificationCalled = false
        let token = realm.addNotificationBlock { (notification, realm) -> Void in
            XCTAssertEqual(realm.configuration.fileURL, self.defaultRealmURL())
            notificationCalled = true
        }
        token.stop()
        try! realm.write {}
        XCTAssertFalse(notificationCalled)
    }

    func testAutorefresh() {
        let realm = try! Realm()
        XCTAssertTrue(realm.shouldAutorefresh, "Autorefresh should default to true")
        realm.shouldAutorefresh = false
        XCTAssertFalse(realm.shouldAutorefresh)
        realm.shouldAutorefresh = true
        XCTAssertTrue(realm.shouldAutorefresh)

        // test that autoreresh is applied
        // we have two notifications, one for opening the realm, and a second when performing our transaction
        let notificationFired = expectation(withDescription: "notification fired")
        let token = realm.addNotificationBlock { _, realm in
            XCTAssertNotNil(realm, "Realm should not be nil")
            notificationFired.fulfill()
        }

        dispatchSyncNewThread {
            let realm = try! Realm()
            try! realm.write {
                realm.createObject(ofType: SwiftStringObject.self, populatedWith: ["string"])
            }
        }
        waitForExpectations(withTimeout: 1, handler: nil)
        token.stop()

        // get object
        let results = realm.allObjects(ofType: SwiftStringObject.self
        )
        XCTAssertEqual(results.count, Int(1), "There should be 1 object of type StringObject")
        XCTAssertEqual(results[0].stringCol, "string", "Value of first column should be 'string'")
    }

    func testRefresh() {
        let realm = try! Realm()
        realm.shouldAutorefresh = false

        // test that autoreresh is not applied
        // we have two notifications, one for opening the realm, and a second when performing our transaction
        let notificationFired = expectation(withDescription: "notification fired")
        let token = realm.addNotificationBlock { _, realm in
            XCTAssertNotNil(realm, "Realm should not be nil")
            notificationFired.fulfill()
        }

        let results = realm.allObjects(ofType: SwiftStringObject.self)
        XCTAssertEqual(results.count, Int(0), "There should be 1 object of type StringObject")

        dispatchSyncNewThread {
            try! Realm().write {
                try! Realm().createObject(ofType: SwiftStringObject.self, populatedWith: ["string"])
                return
            }
        }
        waitForExpectations(withTimeout: 1, handler: nil)
        token.stop()

        XCTAssertEqual(results.count, Int(0), "There should be 1 object of type StringObject")

        // refresh
        realm.refresh()

        XCTAssertEqual(results.count, Int(1), "There should be 1 object of type StringObject")
        XCTAssertEqual(results[0].stringCol, "string", "Value of first column should be 'string'")
    }

    func testInvalidate() {
        let realm = try! Realm()
        let object = SwiftObject()
        try! realm.write {
            realm.add(object)
            return
        }
        realm.invalidate()
        XCTAssertEqual(object.isInvalidated, true)

        try! realm.write {
            realm.add(SwiftObject())
            return
        }
        XCTAssertEqual(realm.allObjects(ofType: SwiftObject.self).count, 2)
        XCTAssertEqual(object.isInvalidated, true)
    }

    func testWriteCopyToPath() {
        let realm = try! Realm()
        try! realm.write {
            realm.add(SwiftObject())
        }
        let fileURL = try! defaultRealmURL().deletingLastPathComponent().appendingPathComponent("copy.realm")
        do {
            try realm.writeCopy(toFileURL: fileURL)
        } catch {
            XCTFail("writeCopyToURL failed")
        }
        autoreleasepool {
            let copy = try! Realm(fileURL: fileURL)
            XCTAssertEqual(1, copy.allObjects(ofType: SwiftObject.self).count)
        }
        try! FileManager.default().removeItem(at: fileURL)
    }

    func testEquals() {
        let realm = try! Realm()
        XCTAssertTrue(try! realm == Realm())

        let testRealm = realmWithTestPath()
        XCTAssertFalse(realm == testRealm)

        dispatchSyncNewThread {
            let otherThreadRealm = try! Realm()
            XCTAssertFalse(realm == otherThreadRealm)
        }
    }
}

#else

class RealmTests: TestCase {
    enum TestError: ErrorType {
        case intentional
    }

    func testFileURL() {
        XCTAssertEqual(try! Realm(fileURL: testRealmURL()).configuration.fileURL,
                       testRealmURL())
    }

    func testReadOnly() {
        autoreleasepool {
            XCTAssertEqual(try! Realm().configuration.readOnly, false)

            try! Realm().write {
                try! Realm().create(SwiftIntObject.self, value: [100])
            }
        }
        let config = Realm.Configuration(fileURL: defaultRealmURL(), readOnly: true)
        let readOnlyRealm = try! Realm(configuration: config)
        XCTAssertEqual(true, readOnlyRealm.configuration.readOnly)
        XCTAssertEqual(1, readOnlyRealm.objects(SwiftIntObject.self).count)

        assertThrows(try! Realm(), "Realm has different readOnly settings")
    }

    func testOpeningInvalidPathThrows() {
        assertFails(Error.FileAccess) {
            try Realm(configuration: Realm.Configuration(fileURL: NSURL(fileURLWithPath: "/dev/null/foo")))
        }
    }

    func testReadOnlyFile() {
        autoreleasepool {
            let realm = try! Realm(fileURL: testRealmURL())
            try! realm.write {
                realm.create(SwiftStringObject.self, value: ["a"])
            }
        }

        let fileManager = NSFileManager.defaultManager()
        try! fileManager.setAttributes([ NSFileImmutable: NSNumber(bool: true) ], ofItemAtPath: testRealmURL().path!)

        // Should not be able to open read-write
        assertFails(Error.FileAccess) {
            try Realm(fileURL: testRealmURL())
        }

        assertSucceeds {
            let realm = try Realm(configuration:
                Realm.Configuration(fileURL: testRealmURL(), readOnly: true))
            XCTAssertEqual(1, realm.objects(SwiftStringObject.self).count)
        }

        try! fileManager.setAttributes([ NSFileImmutable: NSNumber(bool: false) ], ofItemAtPath: testRealmURL().path!)
    }

    func testReadOnlyRealmMustExist() {
        assertFails(Error.FileNotFound) {
            try Realm(configuration:
                Realm.Configuration(fileURL: defaultRealmURL(), readOnly: true))
        }
    }

    func testFilePermissionDenied() {
        autoreleasepool {
            let _ = try! Realm(fileURL: testRealmURL())
        }

        // Make Realm at test path temporarily unreadable
        let fileManager = NSFileManager.defaultManager()
        let permissions = try! fileManager
            .attributesOfItemAtPath(testRealmURL().path!)[NSFilePosixPermissions] as! NSNumber
        try! fileManager.setAttributes([ NSFilePosixPermissions: NSNumber(int: 0000) ],
                                       ofItemAtPath: testRealmURL().path!)

        assertFails(Error.FilePermissionDenied) {
            try Realm(fileURL: testRealmURL())
        }

        try! fileManager.setAttributes([ NSFilePosixPermissions: permissions ], ofItemAtPath: testRealmURL().path!)
    }

    #if DEBUG
    func testFileFormatUpgradeRequiredButDisabled() {
        var config = Realm.Configuration()
        var bundledRealmPath = NSBundle(forClass: RealmTests.self).pathForResource("fileformat-pre-null.realm",
                                                                                   ofType: nil)!
        try! NSFileManager.defaultManager.copyItemAtPath(bundledRealmPath, toPath: config.path)
        config.disableFormatUpgrade = true
        assertFails(Error.FileFormatUpgradeRequired) {
            try Realm(configuration: config)
        }
    }
    #endif

    func testSchema() {
        let schema = try! Realm().schema
        XCTAssert(schema as AnyObject is Schema)
        XCTAssertEqual(1, schema.objectSchema.filter({ $0.className == "SwiftStringObject" }).count)
    }

    func testIsEmpty() {
        let realm = try! Realm()
        XCTAssert(realm.isEmpty, "Realm should be empty on creation.")

        realm.beginWrite()
        realm.create(SwiftStringObject.self, value: ["a"])
        XCTAssertFalse(realm.isEmpty, "Realm should not be empty within a write transaction after adding an object.")
        realm.cancelWrite()

        XCTAssertTrue(realm.isEmpty, "Realm should be empty after canceling a write transaction that added an object.")

        realm.beginWrite()
        realm.create(SwiftStringObject.self, value: ["a"])
        try! realm.commitWrite()
        XCTAssertFalse(realm.isEmpty,
            "Realm should not be empty after committing a write transaction that added an object.")
    }

    func testInit() {
        XCTAssertEqual(try! Realm(fileURL: testRealmURL()).configuration.fileURL,
                       testRealmURL())
    }

    func testInitFailable() {
        autoreleasepool {
            _ = try! Realm()
        }

        NSFileManager.defaultManager().createFileAtPath(defaultRealmURL().path!,
            contents:"a".dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false),
            attributes: nil)

        assertFails(Error.FileAccess) {
            _ = try Realm()
            XCTFail("Realm creation should have failed")
        }
    }

    func testInitInMemory() {
        autoreleasepool {
            let realm = inMemoryRealm("identifier")
            try! realm.write {
                realm.create(SwiftIntObject.self, value: [1])
                return
            }
        }
        let realm = inMemoryRealm("identifier")
        XCTAssertEqual(realm.objects(SwiftIntObject.self).count, 0)

        try! realm.write {
            realm.create(SwiftIntObject.self, value: [1])
            XCTAssertEqual(realm.objects(SwiftIntObject.self).count, 1)

            inMemoryRealm("identifier").create(SwiftIntObject.self, value: [1])
            XCTAssertEqual(realm.objects(SwiftIntObject.self).count, 2)
        }

        let realm2 = inMemoryRealm("identifier2")
        XCTAssertEqual(realm2.objects(SwiftIntObject.self).count, 0)
    }

    func testInitCustomClassList() {
        let configuration = Realm.Configuration(fileURL: Realm.Configuration.defaultConfiguration.fileURL,
            objectTypes: [SwiftStringObject.self])
        XCTAssert(configuration.objectTypes! is [SwiftStringObject.Type])
        let realm = try! Realm(configuration: configuration)
        XCTAssertEqual(["SwiftStringObject"], realm.schema.objectSchema.map { $0.className })
    }

    func testWrite() {
        try! Realm().write {
            self.assertThrows(try! Realm().beginWrite())
            self.assertThrows(try! Realm().write { })
            try! Realm().create(SwiftStringObject.self, value: ["1"])
            XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 1)
        }
        XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 1)
    }

    func testDynamicWrite() {
        try! Realm().write {
            self.assertThrows(try! Realm().beginWrite())
            self.assertThrows(try! Realm().write { })
            try! Realm().dynamicCreate("SwiftStringObject", value: ["1"])
            XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 1)
        }
        XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 1)
    }

    func testDynamicWriteSubscripting() {
        try! Realm().beginWrite()
        let object = try! Realm().dynamicCreate("SwiftStringObject", value: ["1"])
        try! Realm().commitWrite()

        XCTAssertNotNil(object, "Dynamic Object Creation Failed")

        let stringVal = object["stringCol"] as! String
        XCTAssertEqual(stringVal, "1", "Object Subscripting Failed")
    }

    func testBeginWrite() {
        try! Realm().beginWrite()
        assertThrows(try! Realm().beginWrite())
        try! Realm().cancelWrite()
        try! Realm().beginWrite()
        try! Realm().create(SwiftStringObject.self, value: ["1"])
        XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 1)
    }

    func testCommitWrite() {
        try! Realm().beginWrite()
        try! Realm().create(SwiftStringObject.self, value: ["1"])
        try! Realm().commitWrite()
        XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 1)
        try! Realm().beginWrite()
    }

    func testCancelWrite() {
        assertThrows(try! Realm().cancelWrite())
        try! Realm().beginWrite()
        try! Realm().create(SwiftStringObject.self, value: ["1"])
        try! Realm().cancelWrite()
        XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 0)

        try! Realm().write {
            self.assertThrows(self.realmWithTestPath().cancelWrite())
            let object = try! Realm().create(SwiftStringObject)
            try! Realm().cancelWrite()
            XCTAssertTrue(object.invalidated)
            XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 0)
        }
        XCTAssertEqual(try! Realm().objects(SwiftStringObject.self).count, 0)
    }

    func testThrowsWrite() {
        assertFails(TestError.intentional) {
            try Realm().write {
                throw TestError.intentional
            }
        }
        assertFails(TestError.intentional) {
            try Realm().write {
                try! Realm().create(SwiftStringObject.self, value: ["1"])
                throw TestError.intentional
            }
        }
    }

    func testInWriteTransaction() {
        let realm = try! Realm()
        XCTAssertFalse(realm.inWriteTransaction)
        realm.beginWrite()
        XCTAssertTrue(realm.inWriteTransaction)
        realm.cancelWrite()
        try! realm.write {
            XCTAssertTrue(realm.inWriteTransaction)
            realm.cancelWrite()
            XCTAssertFalse(realm.inWriteTransaction)
        }

        realm.beginWrite()
        realm.invalidate()
        XCTAssertFalse(realm.inWriteTransaction)
    }

    func testAddSingleObject() {
        let realm = try! Realm()
        assertThrows(_ = realm.add(SwiftObject()))
        XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
        var defaultRealmObject: SwiftObject!
        try! realm.write {
            defaultRealmObject = SwiftObject()
            realm.add(defaultRealmObject)
            XCTAssertEqual(1, realm.objects(SwiftObject.self).count)
            realm.add(defaultRealmObject)
            XCTAssertEqual(1, realm.objects(SwiftObject.self).count)
        }
        XCTAssertEqual(1, realm.objects(SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(defaultRealmObject))
        }
    }

    func testAddWithUpdateSingleObject() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.objects(SwiftPrimaryStringObject.self).count)
        var defaultRealmObject: SwiftPrimaryStringObject!
        try! realm.write {
            defaultRealmObject = SwiftPrimaryStringObject()
            realm.add(defaultRealmObject, update: true)
            XCTAssertEqual(1, realm.objects(SwiftPrimaryStringObject.self).count)
            realm.add(SwiftPrimaryStringObject(), update: true)
            XCTAssertEqual(1, realm.objects(SwiftPrimaryStringObject.self).count)
        }
        XCTAssertEqual(1, realm.objects(SwiftPrimaryStringObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(defaultRealmObject, update: true))
        }
    }

    func testAddMultipleObjects() {
        let realm = try! Realm()
        assertThrows(_ = realm.add([SwiftObject(), SwiftObject()]))
        XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
        try! realm.write {
            let objs = [SwiftObject(), SwiftObject()]
            realm.add(objs)
            XCTAssertEqual(2, realm.objects(SwiftObject.self).count)
        }
        XCTAssertEqual(2, realm.objects(SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(realm.objects(SwiftObject.self)))
        }
    }

    func testAddWithUpdateMultipleObjects() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.objects(SwiftPrimaryStringObject.self).count)
        try! realm.write {
            let objs = [SwiftPrimaryStringObject(), SwiftPrimaryStringObject()]
            realm.add(objs, update: true)
            XCTAssertEqual(1, realm.objects(SwiftPrimaryStringObject.self).count)
        }
        XCTAssertEqual(1, realm.objects(SwiftPrimaryStringObject.self).count)

        let testRealm = realmWithTestPath()
        try! testRealm.write {
            self.assertThrows(_ = testRealm.add(realm.objects(SwiftPrimaryStringObject.self), update: true))
        }
    }

    // create() tests are in ObjectCreationTests.swift

    func testDeleteSingleObject() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
        assertThrows(_ = realm.delete(SwiftObject()))
        var defaultRealmObject: SwiftObject!
        try! realm.write {
            defaultRealmObject = SwiftObject()
            self.assertThrows(_ = realm.delete(defaultRealmObject))
            XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
            realm.add(defaultRealmObject)
            XCTAssertEqual(1, realm.objects(SwiftObject.self).count)
            realm.delete(defaultRealmObject)
            XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
        }
        assertThrows(_ = realm.delete(defaultRealmObject))
        XCTAssertEqual(0, realm.objects(SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        assertThrows(_ = testRealm.delete(defaultRealmObject))
        try! testRealm.write {
            self.assertThrows(_ = testRealm.delete(defaultRealmObject))
        }
    }

    func testDeleteSequenceOfObjects() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
        var objs: [SwiftObject]!
        try! realm.write {
            objs = [SwiftObject(), SwiftObject()]
            realm.add(objs)
            XCTAssertEqual(2, realm.objects(SwiftObject.self).count)
            realm.delete(objs)
            XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
        }
        XCTAssertEqual(0, realm.objects(SwiftObject.self).count)

        let testRealm = realmWithTestPath()
        assertThrows(_ = testRealm.delete(objs))
        try! testRealm.write {
            self.assertThrows(_ = testRealm.delete(objs))
        }
    }

    func testDeleteListOfObjects() {
        let realm = try! Realm()
        XCTAssertEqual(0, realm.objects(SwiftCompanyObject.self).count)
        try! realm.write {
            let obj = SwiftCompanyObject()
            obj.employees.append(SwiftEmployeeObject())
            realm.add(obj)
            XCTAssertEqual(1, realm.objects(SwiftEmployeeObject.self).count)
            realm.delete(obj.employees)
            XCTAssertEqual(0, obj.employees.count)
            XCTAssertEqual(0, realm.objects(SwiftEmployeeObject.self).count)
        }
        XCTAssertEqual(0, realm.objects(SwiftEmployeeObject.self).count)
    }

    func testDeleteResults() {
        let realm = try! Realm(fileURL: testRealmURL())
        XCTAssertEqual(0, realm.objects(SwiftCompanyObject.self).count)
        try! realm.write {
            realm.add(SwiftIntObject(value: [1]))
            realm.add(SwiftIntObject(value: [1]))
            realm.add(SwiftIntObject(value: [2]))
            XCTAssertEqual(3, realm.objects(SwiftIntObject.self).count)
            realm.delete(realm.objects(SwiftIntObject.self).filter("intCol = 1"))
            XCTAssertEqual(1, realm.objects(SwiftIntObject.self).count)
        }
        XCTAssertEqual(1, realm.objects(SwiftIntObject.self).count)
    }

    func testDeleteAll() {
        let realm = try! Realm()
        try! realm.write {
            realm.add(SwiftObject())
            XCTAssertEqual(1, realm.objects(SwiftObject.self).count)
            realm.deleteAll()
            XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
        }
        XCTAssertEqual(0, realm.objects(SwiftObject.self).count)
    }

    func testObjects() {
        try! Realm().write {
            try! Realm().create(SwiftIntObject.self, value: [100])
            try! Realm().create(SwiftIntObject.self, value: [200])
            try! Realm().create(SwiftIntObject.self, value: [300])
        }

        XCTAssertEqual(0, try! Realm().objects(SwiftStringObject.self).count)
        XCTAssertEqual(3, try! Realm().objects(SwiftIntObject.self).count)
        assertThrows(try! Realm().objects(Object.self))
    }

    func testDynamicObjects() {
        try! Realm().write {
            try! Realm().create(SwiftIntObject.self, value: [100])
            try! Realm().create(SwiftIntObject.self, value: [200])
            try! Realm().create(SwiftIntObject.self, value: [300])
        }

        XCTAssertEqual(0, try! Realm().dynamicObjects("SwiftStringObject").count)
        XCTAssertEqual(3, try! Realm().dynamicObjects("SwiftIntObject").count)
        assertThrows(try! Realm().dynamicObjects("Object"))
    }

    func testDynamicObjectProperties() {
        try! Realm().write {
            try! Realm().create(SwiftObject)
        }

        let object = try! Realm().dynamicObjects("SwiftObject")[0]
        let dictionary = SwiftObject.defaultValues()

        XCTAssertEqual(object["boolCol"] as? NSNumber, dictionary["boolCol"] as! NSNumber?)
        XCTAssertEqual(object["intCol"] as? NSNumber, dictionary["intCol"] as! NSNumber?)
        XCTAssertEqual(object["floatCol"] as? NSNumber, dictionary["floatCol"] as! Float?)
        XCTAssertEqual(object["doubleCol"] as? NSNumber, dictionary["doubleCol"] as! Double?)
        XCTAssertEqual(object["stringCol"] as! String?, dictionary["stringCol"] as! String?)
        XCTAssertEqual(object["binaryCol"] as! NSData?, dictionary["binaryCol"] as! NSData?)
        XCTAssertEqual(object["dateCol"] as! NSDate?, dictionary["dateCol"] as! NSDate?)
        XCTAssertEqual(object["objectCol"]?.boolCol, false)
    }

    func testDynamicObjectOptionalProperties() {
        try! Realm().write {
            try! Realm().create(SwiftOptionalDefaultValuesObject)
        }

        let object = try! Realm().dynamicObjects("SwiftOptionalDefaultValuesObject")[0]
        let dictionary = SwiftOptionalDefaultValuesObject.defaultValues()

        XCTAssertEqual(object["optIntCol"] as? NSNumber, dictionary["optIntCol"] as! NSNumber?)
        XCTAssertEqual(object["optInt8Col"] as? NSNumber, dictionary["optInt8Col"] as! NSNumber?)
        XCTAssertEqual(object["optInt16Col"] as? NSNumber, dictionary["optInt16Col"] as! NSNumber?)
        XCTAssertEqual(object["optInt32Col"] as? NSNumber, dictionary["optInt32Col"] as! NSNumber?)
        XCTAssertEqual(object["optInt64Col"] as? NSNumber, dictionary["optInt64Col"] as! NSNumber?)
        XCTAssertEqual(object["optFloatCol"] as? NSNumber, dictionary["optFloatCol"] as! Float?)
        XCTAssertEqual(object["optDoubleCol"] as? NSNumber, dictionary["optDoubleCol"] as! Double?)
        XCTAssertEqual(object["optStringCol"] as! String?, dictionary["optStringCol"] as! String?)
        XCTAssertEqual(object["optNSStringCol"] as! String?, dictionary["optNSStringCol"] as! String?)
        XCTAssertEqual(object["optBinaryCol"] as! NSData?, dictionary["optBinaryCol"] as! NSData?)
        XCTAssertEqual(object["optDateCol"] as! NSDate?, dictionary["optDateCol"] as! NSDate?)
        XCTAssertEqual(object["optObjectCol"]?.boolCol, true)
    }

    func testObjectForPrimaryKey() {
        let intTypes: [Object.Type] = [SwiftPrimaryIntObject.self,
                                       SwiftPrimaryInt8Object.self,
                                       SwiftPrimaryInt16Object.self,
                                       SwiftPrimaryInt32Object.self,
                                       SwiftPrimaryInt64Object.self]
        let optionalIntTypes: [Object.Type] = [SwiftPrimaryOptionalIntObject.self,
                                               SwiftPrimaryOptionalInt8Object.self,
                                               SwiftPrimaryOptionalInt16Object.self,
                                               SwiftPrimaryOptionalInt32Object.self,
                                               SwiftPrimaryOptionalInt64Object.self]

        let realm = try! Realm()
        try! realm.write {
            realm.create(SwiftPrimaryStringObject.self, value: ["a", 1])
            realm.create(SwiftPrimaryStringObject.self, value: ["b", 2])

            realm.create(SwiftPrimaryOptionalStringObject.self, value: [NSNull(), 1])
            realm.create(SwiftPrimaryOptionalStringObject.self, value: ["b", 2])

            func createIntObject(objectType: Object.Type) {
                realm.create(objectType, value: ["a", 1])
                realm.create(objectType, value: ["b", 2])
            }

            func createOptionalIntObject(objectType: Object.Type) {
                realm.create(objectType, value: ["a", NSNull()])
                realm.create(objectType, value: ["b", 2])
            }

            for type in intTypes {
                createIntObject(type)
            }

            for type in optionalIntTypes {
                createOptionalIntObject(type)
            }
        }

        do {
            // When this is directly inside the XCTAssertNotNil, it doesn't work
            let object = realm.objectForPrimaryKey(SwiftPrimaryStringObject.self, key: "a")
            XCTAssertNotNil(object)

            // When this is directly inside the XCTAssertNil, it fails for some reason
            let missingObject = realm.objectForPrimaryKey(SwiftPrimaryStringObject.self, key: "z")
            XCTAssertNil(missingObject)
        }

        do {
            let object1 = realm.objectForPrimaryKey(SwiftPrimaryOptionalStringObject.self, key: NSNull())
            XCTAssertNotNil(object1)

            let object2 = realm.objectForPrimaryKey(SwiftPrimaryOptionalStringObject.self, key: nil)
            XCTAssertEqual(object1, object2)

            let object3 = realm.objectForPrimaryKey(SwiftPrimaryOptionalStringObject.self, key: "b")
            XCTAssertNotNil(object3)

            let missingObject = realm.objectForPrimaryKey(SwiftPrimaryOptionalStringObject.self, key: "z")
            XCTAssertNil(missingObject)
        }

        func assertIntObject(objectType: Object.Type) {
            let object = realm.objectForPrimaryKey(objectType, key: 1)
            XCTAssertNotNil(object)

            let missingObject = realm.objectForPrimaryKey(objectType, key: 0)
            XCTAssertNil(missingObject)
        }

        func assertOptionalIntObject(objectType: Object.Type) {
            let object1 = realm.objectForPrimaryKey(objectType, key: NSNull())
            XCTAssertNotNil(object1)

            let object2 = realm.objectForPrimaryKey(objectType, key: nil)
            XCTAssertEqual(object1, object2)

            let object3 = realm.objectForPrimaryKey(objectType, key: 2)
            XCTAssertNotNil(object3)

            let missingObject = realm.objectForPrimaryKey(objectType, key: 0)
            XCTAssertNil(missingObject)
        }

        for type in intTypes {
            assertIntObject(type)
        }

        for type in optionalIntTypes {
            assertOptionalIntObject(type)
        }
    }

    func testDynamicObjectForPrimaryKey() {
        let intTypes: [Object.Type] = [SwiftPrimaryIntObject.self,
                                       SwiftPrimaryInt8Object.self,
                                       SwiftPrimaryInt16Object.self,
                                       SwiftPrimaryInt32Object.self,
                                       SwiftPrimaryInt64Object.self]
        let optionalIntTypes: [Object.Type] = [SwiftPrimaryOptionalIntObject.self,
                                               SwiftPrimaryOptionalInt8Object.self,
                                               SwiftPrimaryOptionalInt16Object.self,
                                               SwiftPrimaryOptionalInt32Object.self,
                                               SwiftPrimaryOptionalInt64Object.self]

        let realm = try! Realm()
        try! realm.write {
            realm.create(SwiftPrimaryStringObject.self, value: ["a", 1])
            realm.create(SwiftPrimaryStringObject.self, value: ["b", 2])

            realm.create(SwiftPrimaryOptionalStringObject.self, value: [NSNull(), 1])
            realm.create(SwiftPrimaryOptionalStringObject.self, value: ["b", 2])

            func createIntObject(objectType: Object.Type) {
                realm.create(objectType, value: ["a", 1])
                realm.create(objectType, value: ["b", 2])
            }

            func createOptionalIntObject(objectType: Object.Type) {
                realm.create(objectType, value: ["a", NSNull()])
                realm.create(objectType, value: ["b", 2])
            }

            for type in intTypes {
                createIntObject(type)
            }

            for type in optionalIntTypes {
                createOptionalIntObject(type)
            }
        }

        XCTAssertNotNil(realm.dynamicObjectForPrimaryKey(String(SwiftPrimaryStringObject), key: "a"))
        XCTAssertNil(realm.dynamicObjectForPrimaryKey(String(SwiftPrimaryStringObject), key: "z"))

        XCTAssertNotNil(realm.dynamicObjectForPrimaryKey(String(SwiftPrimaryOptionalStringObject), key: NSNull()))
        XCTAssertEqual(realm.dynamicObjectForPrimaryKey(String(SwiftPrimaryOptionalStringObject), key: NSNull()),
                       realm.dynamicObjectForPrimaryKey(String(SwiftPrimaryOptionalStringObject), key: nil))
        XCTAssertNotNil(realm.dynamicObjectForPrimaryKey(String(SwiftPrimaryOptionalStringObject), key: "b"))
        XCTAssertNil(realm.dynamicObjectForPrimaryKey(String(SwiftPrimaryOptionalStringObject), key: "z"))

        func assertIntObject(objectType: Object.Type) {
            XCTAssertNotNil(realm.dynamicObjectForPrimaryKey(String(objectType), key: 1))
            XCTAssertNil(realm.dynamicObjectForPrimaryKey(String(objectType), key: 0))
        }

        func assertOptionalIntObject(objectType: Object.Type) {
            XCTAssertNotNil(realm.dynamicObjectForPrimaryKey(String(objectType), key: NSNull()))
            XCTAssertEqual(realm.dynamicObjectForPrimaryKey(String(objectType), key: NSNull()),
                           realm.dynamicObjectForPrimaryKey(String(objectType), key: nil))
            XCTAssertNotNil(realm.dynamicObjectForPrimaryKey(String(objectType), key: 2))
            XCTAssertNil(realm.dynamicObjectForPrimaryKey(String(objectType), key: 0))
        }

        for type in intTypes {
            assertIntObject(type)
        }

        for type in optionalIntTypes {
            assertOptionalIntObject(type)
        }
    }

    func testDynamicObjectForPrimaryKeySubscripting() {
        let realm = try! Realm()
        try! realm.write {
            realm.create(SwiftPrimaryStringObject.self, value: ["a", 1])
        }

        let object = realm.dynamicObjectForPrimaryKey("SwiftPrimaryStringObject", key: "a")

        let stringVal = object!["stringCol"] as! String

        XCTAssertEqual(stringVal, "a", "Object Subscripting Failed!")
    }

    func testAddNotificationBlock() {
        let realm = try! Realm()
        var notificationCalled = false
        let token = realm.addNotificationBlock { _, realm in
            XCTAssertEqual(realm.configuration.fileURL, self.defaultRealmURL())
            notificationCalled = true
        }
        XCTAssertFalse(notificationCalled)
        try! realm.write {}
        XCTAssertTrue(notificationCalled)
        token.stop()
    }

    func testRemoveNotification() {
        let realm = try! Realm()
        var notificationCalled = false
        let token = realm.addNotificationBlock { (notification, realm) -> Void in
            XCTAssertEqual(realm.configuration.fileURL, self.defaultRealmURL())
            notificationCalled = true
        }
        token.stop()
        try! realm.write {}
        XCTAssertFalse(notificationCalled)
    }

    func testAutorefresh() {
        let realm = try! Realm()
        XCTAssertTrue(realm.autorefresh, "Autorefresh should default to true")
        realm.autorefresh = false
        XCTAssertFalse(realm.autorefresh)
        realm.autorefresh = true
        XCTAssertTrue(realm.autorefresh)

        // test that autoreresh is applied
        // we have two notifications, one for opening the realm, and a second when performing our transaction
        let notificationFired = expectationWithDescription("notification fired")
        let token = realm.addNotificationBlock { _, realm in
            XCTAssertNotNil(realm, "Realm should not be nil")
            notificationFired.fulfill()
        }

        dispatchSyncNewThread {
            let realm = try! Realm()
            try! realm.write {
                realm.create(SwiftStringObject.self, value: ["string"])
            }
        }
        waitForExpectationsWithTimeout(1, handler: nil)
        token.stop()

        // get object
        let results = realm.objects(SwiftStringObject.self)
        XCTAssertEqual(results.count, Int(1), "There should be 1 object of type StringObject")
        XCTAssertEqual(results[0].stringCol, "string", "Value of first column should be 'string'")
    }

    func testRefresh() {
        let realm = try! Realm()
        realm.autorefresh = false

        // test that autoreresh is not applied
        // we have two notifications, one for opening the realm, and a second when performing our transaction
        let notificationFired = expectationWithDescription("notification fired")
        let token = realm.addNotificationBlock { _, realm in
            XCTAssertNotNil(realm, "Realm should not be nil")
            notificationFired.fulfill()
        }

        let results = realm.objects(SwiftStringObject.self)
        XCTAssertEqual(results.count, Int(0), "There should be 1 object of type StringObject")

        dispatchSyncNewThread {
            try! Realm().write {
                try! Realm().create(SwiftStringObject.self, value: ["string"])
                return
            }
        }
        waitForExpectationsWithTimeout(1, handler: nil)
        token.stop()

        XCTAssertEqual(results.count, Int(0), "There should be 1 object of type StringObject")

        // refresh
        realm.refresh()

        XCTAssertEqual(results.count, Int(1), "There should be 1 object of type StringObject")
        XCTAssertEqual(results[0].stringCol, "string", "Value of first column should be 'string'")
    }

    func testInvalidate() {
        let realm = try! Realm()
        let object = SwiftObject()
        try! realm.write {
            realm.add(object)
            return
        }
        realm.invalidate()
        XCTAssertEqual(object.invalidated, true)

        try! realm.write {
            realm.add(SwiftObject())
            return
        }
        XCTAssertEqual(realm.objects(SwiftObject.self).count, 2)
        XCTAssertEqual(object.invalidated, true)
    }

    func testWriteCopyToPath() {
        let realm = try! Realm()
        try! realm.write {
            realm.add(SwiftObject())
        }
        let fileURL = defaultRealmURL().URLByDeletingLastPathComponent!
            .URLByAppendingPathComponent("copy.realm")
        do {
            try realm.writeCopyToURL(fileURL)
        } catch {
            XCTFail("writeCopyToURL failed")
        }
        autoreleasepool {
            let copy = try! Realm(fileURL: fileURL)
            XCTAssertEqual(1, copy.objects(SwiftObject.self).count)
        }
        try! NSFileManager.defaultManager().removeItemAtURL(fileURL)
    }

    func testEquals() {
        let realm = try! Realm()
        XCTAssertTrue(try! realm == Realm())

        let testRealm = realmWithTestPath()
        XCTAssertFalse(realm == testRealm)

        dispatchSyncNewThread {
            let otherThreadRealm = try! Realm()
            XCTAssertFalse(realm == otherThreadRealm)
        }
    }
}

#endif
