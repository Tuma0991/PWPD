# UC05 — Manage Contacts

| Field | Detail |
|-------|--------|
| **Use Case ID** | UC05 |
| **Use Case Name** | Manage Emergency Contacts |
| **Actor(s)** | Guardian / Parent |
| **Description** | The guardian adds, edits, and removes emergency contacts. Contacts can be dialed with one tap directly from the contact list. |
| **Precondition** | The guardian is logged in. |
| **Postcondition** | Contact changes are saved and available for tap-to-dial. |

**Normal Flow — Viewing**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 1 | Guardian | Navigate | Navigates to the Contacts tab. |
| 2 | System | Display | Displays contacts in two groups: priority emergency contacts at the top, and other contacts below. Each contact shows name, relationship, and a phone icon. |

**Normal Flow — Adding**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 3 | Guardian | Initiate | Taps the add button. |
| 4 | Guardian | Enter | Fills in the contact's name, phone number, and relationship, and sets whether they are a priority emergency contact. |
| 5 | Guardian | Save | Taps save. |
| 6 | System | Validate | Validates the information (name and phone number are required) and saves the contact. |

**Normal Flow — Editing or Deleting**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 7 | Guardian | Modify | Taps a contact to edit, modifies the information, and saves — or taps delete and confirms. |
| 8 | System | Update | Updates or removes the contact. |

**Normal Flow — Calling a Contact**

| Step | Performed by | Action Word/s | Action |
|------|-------|--------------|--------|
| 9 | Guardian | Initiate | Taps the phone icon on any contact. |
| 10 | System | Open | Opens the phone dialer with the contact's number pre-filled. |
| 11 | Guardian | Call | Presses the call button in the dialer to place the call. |

**Alternative Flows**

| Step | Condition | Action Word/s | Action |
|------|-----------|--------------|--------|
| 6a | Name is empty or phone number is invalid | Reject | System shows a validation error and asks the guardian to correct the fields. |

| **Includes** | UC10 — Store Persistent Data |
