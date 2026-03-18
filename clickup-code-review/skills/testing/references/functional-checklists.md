# Functional Test Checklists (v5.2.3)

QA Specialist reference for Level 2 (Funcional) testing. Use these checklists for each page type encountered. All items must be verified before marking a page as PASS.

**Ver `testing-protocol.md`** para procedimentos Chrome DevTools MCP passo-a-passo.

**REGRA v5.2.3:** `take_snapshot()` é o PRIMEIRO passo em TODAS as páginas. O snapshot revela os elementos interactivos — sem isto, o agent não sabe o que testar.

---

## Navigation Consistency (OBRIGATÓRIO — todas as páginas)

- [ ] Página alcançável via menu/sidebar? (se não → "página órfã" finding)
- [ ] Breadcrumbs presentes e correctos?
- [ ] Back button/link funciona?
- [ ] Menu item activo corresponde à página actual?

---

## Design System Consistency (OBRIGATÓRIO em funcional/completo)

- [ ] Botões primários: mesmas classes/estilo que baseline?
- [ ] Tabelas: mesmo componente/estrutura que baseline?
- [ ] Forms: labels, inputs, error messages consistentes com baseline?
- [ ] Cards/containers: layout consistente com baseline?
- [ ] Tipografia: headings, body text consistentes?
- [ ] Se desvio encontrado → registar + incluir no relatório

---

## Listing / Index Pages

**PRIMEIRO:** Snapshot da página — identificar TODOS os elementos interactivos

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

**PRIMEIRO:** Snapshot da página — identificar TODOS os campos e botões

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

**PRIMEIRO:** Snapshot da página — identificar TODOS os campos preenchidos e botões

- [ ] Page loads with existing data pre-filled in fields
- [ ] Modify at least one field with new test value
- [ ] Submit → verify redirect or success flash message
- [ ] Verify updated value persists (navigate back to show/list → check)
- [ ] Cancel button (if exists) → verify returns without saving

---

## Show / Detail Pages

**PRIMEIRO:** Snapshot da página — identificar TODAS as secções e botões de acção

- [ ] All expected fields/sections visible (not just skeleton/loading state)
- [ ] Related items visible (if page shows relationships)
- [ ] Action buttons visible (Edit, Delete, Back)
- [ ] Edit button → click → navigate to edit form
- [ ] Back button → click → navigate to listing

---

## Delete Actions

**PRIMEIRO:** Snapshot — identificar botão de delete e tipo de confirmação (dialog/modal)

- [ ] Delete button exists (in listing row or show page)
- [ ] Click delete → confirmation dialog/modal appears
- [ ] Cancel confirmation → record still exists
- [ ] Confirm deletion → verify redirect to listing
- [ ] Verify record no longer appears in listing after delete

---

## Dashboard Pages

**PRIMEIRO:** Snapshot da página — identificar TODOS os widgets, cards, e elementos interactivos

- [ ] All metric cards/widgets render (no empty/broken sections)
- [ ] Charts render with data (canvas elements not empty)
- [ ] Date range filters (if any) → change period → verify data updates
- [ ] Quick action buttons (if any) → click → verify navigation
- [ ] No console errors after full render (wait 3s after initial load)

---

## Settings / Configuration Pages

**PRIMEIRO:** Snapshot da página — identificar TODOS os campos de configuração

- [ ] All settings fields visible and pre-populated
- [ ] Modify a safe setting (e.g., display preference, not critical config)
- [ ] Save → verify success message
- [ ] Verify saved setting persists after page reload

---

## Import / Export Pages

**PRIMEIRO:** Snapshot da página — identificar botões de export e inputs de upload

**Export:**
- [ ] Export button exists → click → verify download starts OR file listed
- [ ] Exported file is non-empty (if verifiable via network request)

**Import:**
- [ ] File upload input exists
- [ ] Upload valid sample file → submit → verify success or processing status
- [ ] Upload invalid file type → verify validation error shown (not 500)

---

## Modal / Dialog Interactions

**PRIMEIRO:** Snapshot antes de trigger — identificar botão que abre o modal

- [ ] Trigger button exists → click → modal opens
- [ ] Modal renders correctly (not cut off, not empty)
- [ ] Interaction inside modal (fill form, click button)
- [ ] Confirm action → modal closes, expected result occurs
- [ ] Cancel/close → modal closes, no changes saved
- [ ] Keyboard Esc → modal closes (if applicable)

---

## State Transition Actions (Approval/Status Flows)

**PRIMEIRO:** Snapshot da página — identificar botões/dropdowns de mudança de estado

- [ ] Status change buttons/dropdowns visible
- [ ] Change status (e.g., pending → active) → verify status updates in UI
- [ ] Approval action → verify approved indicator shown
- [ ] Rejection action → verify status reflected + reason field (if applicable)
- [ ] Status history/log updated (if visible in UI)

---

## QA Specialist Notes

- `take_snapshot()` é o PRIMEIRO passo em CADA página — sem excepções
- Screenshots are temporary debugging tools — **DELETE before shutdown** (MANDATORY)
- When a test fails: record in `{REVIEW_DIR}/qa/qa-progress.md` with URL, action, expected vs actual
- If test cannot be completed (missing test data, permissions): log as SKIPPED with reason
- Every interactive element counts — do not skip buttons, links, or filters
- Registar NAV_METHOD (sidebar/link/url_directa) para cada página no progress log
