import Foundation
import Contacts

/// Looks up contacts for iMessage integration
class ContactService {
    static let shared = ContactService()

    private let store = CNContactStore()

    /// Request access to contacts
    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            print("Contacts access error: \(error)")
            return false
        }
    }

    /// Find a contact by name, returns (fullName, phoneNumber) or nil
    func findContact(named query: String) async -> (name: String, phone: String)? {
        let hasAccess = await requestAccess()
        guard hasAccess else { return nil }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: query)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            // Return the first contact with a phone number
            for contact in contacts {
                if let phone = contact.phoneNumbers.first?.value.stringValue {
                    let name = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    return (name: name.isEmpty ? query : name, phone: phone)
                }
            }
        } catch {
            print("Contact search error: \(error)")
        }

        return nil
    }

    /// Find a contact by name, returns (fullName, emailAddress) or nil
    func findContactEmail(named query: String) async -> (name: String, email: String)? {
        let results = await findAllContactEmails(named: query)
        return results.first
    }

    /// Find ALL contacts matching a name that have email addresses
    func findAllContactEmails(named query: String) async -> [(name: String, email: String)] {
        let hasAccess = await requestAccess()
        guard hasAccess else { return [] }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: query)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            var results: [(name: String, email: String)] = []
            for contact in contacts {
                if let email = contact.emailAddresses.first?.value as String? {
                    let name = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    results.append((name: name.isEmpty ? query : name, email: email))
                }
            }
            return results
        } catch {
            print("Contact email search error: \(error)")
        }

        return []
    }
}
