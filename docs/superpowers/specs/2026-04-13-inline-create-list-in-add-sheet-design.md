# Inline "Create new list" in Add-to-List sheet

**Date:** 2026-04-13
**Scope:** `lib/presentation/widgets/products/add_to_list_sheet.dart` (single-file change)

## Problem

Users browsing products can only add to *existing* shopping lists via the add-to-list bottom sheet. If no suitable list exists, they must close the sheet, navigate to the Lists tab, create a list, return to Browse, find the product again, and re-open the sheet. This round-trip hurts the core "see a good price → add it" flow.

## Goal

Let users create a new shopping list directly from the add-to-list bottom sheet, then add the product to it — without leaving the sheet.

## Design

### UI

Inside `_buildListSelector`, append a "+ Create new list" tile below the existing lists. In the empty state (no lists yet), this tile replaces the "Create a list first from the Lists tab" hint.

Tapping the tile toggles an inline compact form that swaps in place:

- `TextField` for list name — autofocused, single line, 40-char max, "My shopping list" hint
- Row of two buttons: "Cancel" (text) and "Create" (filled, primary color)
- Error text shown inline below the field on validation/creation failure
- While creation is in flight: Create button disabled, shows small spinner; Cancel disabled

No store picker, no color picker — kept deliberately minimal for speed. Store defaults to `widget.retailer` (the product being added), color defaults to `'Green'`. Users who want to customize those still have the full Create List screen.

### State

Four additions to `_AddToListSheetState`:

```dart
bool _isCreatingList = false;
bool _isCreatingListInFlight = false;
final _newListController = TextEditingController();
String? _createListError;
```

Dispose `_newListController` in `dispose()`.

### Create flow

1. User taps "+ Create new list" → `setState(_isCreatingList = true)`.
2. User types name, taps Create.
3. Validate: trim, require non-empty, ≤40 chars. On failure set `_createListError` and return.
4. Set `_isCreatingListInFlight = true`.
5. Call `ref.read(listNotifierProvider.notifier).createList(listName: name, storeName: widget.retailer, listColour: 'Green')`.
6. On success (non-null result):
   - `_selectedListId = list.shoppingListId`
   - `_isCreatingList = false`
   - Clear controller and error
   - `userListsProvider` is already invalidated inside `createList()`, so the new list appears in the selector automatically
7. On failure: set `_createListError = 'Could not create list. Try again.'`, leave form open.
8. Always clear `_isCreatingListInFlight`.

### Edge cases

- **User taps "Add to List" while mid-create:** `_handleAdd` checks `_isCreatingList` first; if true, show inline message "Finish creating your list first" (via `_createListError`) and abort. No snackbar.
- **Retailer is empty string:** fall back to `'Pick n Pay'` (matches `CreateListScreen` default).
- **Offline:** `createList()` already handles offline by creating a local temp list and queuing sync — no special handling needed here.

### Testing

Manual smoke test:
- Create list from empty state, add product → list appears in Lists tab with correct retailer
- Create list when other lists exist, ensure new one is auto-selected
- Cancel mid-creation returns to list selector unchanged
- Create with empty/whitespace name shows inline error
- Offline create (airplane mode) still creates the list locally

## Non-goals

- No store/color picker in the inline form (YAGNI — full screen still exists)
- No edit/delete from the sheet
- No sharing/collaboration changes
