import Foundation

UserDefaults.standard.set(30, forKey: "testKey")
let obj = UserDefaults.standard.object(forKey: "testKey")
print("Obj: \(String(describing: obj))")
let casted = obj as? Int
print("Casted: \(String(describing: casted))")
