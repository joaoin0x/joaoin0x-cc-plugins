# Functional Test Checklists (v5.2.1)

QA Specialist reference for Level 2 (Funcional) testing. Use these checklists for each page type encountered. All items must be verified before marking a page as PASS.

**Ver `testing-protocol.md`** para procedimentos Chrome DevTools MCP passo-a-passo.

---

## Listing / Index Pages

- [ ] Table/list renders with data (not empty unless expected)
- [ ] Search input exists → fill + submit → verify results update
- [ ] Clear search → verify all results return
- [ ] Pagination exists → click next → verify different rows displayed
- [ ] Pagination → click previous → verify navigation back
- [ ] Filter dropdowns exist → select option → verify table filters
- [ ] Reset filters → verify all results return
- [ ] Sorting headers (if any) → click → verify order changes
- [ ] Bulk action checkboxes (if any) → select all → verify action button activates
- [ ] Create/Add button exists → click → navigate to create form
- [ ] Per-row actions (edit, delete, view) → verify buttons/links visible
- [ ] Empty state message (when no data) → verify message shown (if applicable)

---

## Form / Create Pages

- [ ] All required fields detected (marked with `*` or `required` attribute)
- [ ] Required fields filled with valid test data
- [ ] Optional fields sampled (at least 2-3 filled)
- [ ] Submit button visible and enabled
- [ ] Form submitted → verify redirect or success flash message
- [ ] Success flash/toast message visible after submission
- [ ] Record appears in listing after creation (navigate back to list → verify)
- [ ] Validation: submit empty form → verify validation errors shown (not 500)
- [ ] Validation: invalid email format → verify specific error (if email field exists)

---

## Edit Pages

- [ ] Page loads with existing data pre-filled in fields
- [ ] Modify at least one field with new test value
- [ ] Submit → verify redirect or success flash message
- [ ] Verify updated value persists (navigate back to show/list → check)
- [ ] Cancel button (if exists) → verify returns without saving

---

## Show / Detail Pages

- [ ] All expected fields/sections visible (not just skeleton/loading state)
- [ ] Related items visible (if page shows relationships)
- [ ] Action buttons visible (Edit, Delete, Back)
- [ ] Edit button → click → navigate to edit form
- [ ] Back button → click → navigate to listing

---

## Delete Actions

- [ ] Delete button exists (in listing row or show page)
- [ ] Click delete → confirmation dialog/modal appears
- [ ] Cancel confirmation → record still exists
- [ ] Confirm deletion → verify redirect to listing
- [ ] Verify record no longer appears in listing after delete

---

## Dashboard Pages

- [ ] All metric cards/widgets render (no empty/broken sections)
- [ ] Charts render with data (canvas elements not empty)
- [ ] Date range filters (if any) → change period → verify data updates
- [ ] Quick action buttons (if any) → click → verify navigation
- [ ] No console errors after full render (wait 3s after initial load)

---

## Settings / Configuration Pages

- [ ] All settings fields visible and pre-populated
- [ ] Modify a safe setting (e.g., display preference, not critical config)
- [ ] Save → verify success message
- [ ] Verify saved setting persists after page reload

---

## Import / Export Pages

**Export:**
- [ ] Export button exists → click → verify download starts OR file listed
- [ ] Exported file is non-empty (if verifiable via network request)

**Import:**
- [ ] File upload input exists
- [ ] Upload valid sample file → submit → verify success or processing status
- [ ] Upload invalid file type → verify validation error shown (not 500)

---

## Modal / Dialog Interactions

- [ ] Trigger button exists → click → modal opens
- [ ] Modal renders correctly (not cut off, not empty)
- [ ] Interaction inside modal (fill form, click button)
- [ ] Confirm action → modal closes, expected result occurs
- [ ] Cancel/close → modal closes, no changes saved
- [ ] Keyboard Esc → modal closes (if applicable)

---

## State Transition Actions (Approval/Status Flows)

- [ ] Status change buttons/dropdowns visible
- [ ] Change status (e.g., pending → active) → verify status updates in UI
- [ ] Approval action → verify approved indicator shown
- [ ] Rejection action → verify status reflected + reason field (if applicable)
- [ ] Status history/log updated (if visible in UI)

---

## QA Specialist Notes

- Screenshots are temporary debugging tools — **DELETE before shutdown** (MANDATORY)
- When a test fails: record in `{REVIEW_DIR}/qa/qa-progress.md` with URL, action, expected vs actual
- If test cannot be completed (missing test data, permissions): log as SKIPPED with reason
- Every interactive element counts — do not skip buttons, links, or filters
