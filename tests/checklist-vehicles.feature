# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_dealership — Vehicles

  @kora_dealership @checklist @checklist:kora_dealership:creator-open @cat:vehicles @needs:admin
  Scenario: /dealershipcreator admin creator
    """
    Checklist test: As admin run /dealershipcreator; list of dealerships with Create dealership button. Non-admin is denied.
    """
    When I run the command "/dealershipcreator"
    Then I confirm: a list of dealerships opens with a Create dealership button (as admin)
    When I manually: ask a non-admin second player to run /dealershipcreator
    Then I confirm: the other player is denied and the creator does not open

  @kora_dealership @checklist @checklist:kora_dealership:creator-data @cat:vehicles @needs:admin
  Scenario: Edit dealership data and access
    """
    Checklist test: In creator set name, access (Public / For sale with price / Owned with owner citizenid); save shows 'Saved'.
    """
    When I manually: run /dealershipcreator
    Then the "qbdealership:creator" app should be open
    When I manually: open a dealership in the creator
    And I manually: set the dealership name
    And I manually: set access to Public, then For sale with a price, then Owned with an owner citizenid
    And I manually: click Save
    Then I should see a notification containing "Saved"

  @kora_dealership @checklist @checklist:kora_dealership:creator-zone @cat:vehicles @needs:admin
  Scenario: Draw and clear dealership zone
    """
    Checklist test: Zone Management: Draw zone, place polygon points, Redraw/Clear zone; customers must be inside it to use the shop.
    """
    When I manually: run /dealershipcreator
    Then the "qbdealership:creator" app should be open
    When I manually: open a dealership, go to Zone Management and click Draw zone
    And I manually: place several polygon points
    Then I confirm: the zone polygon is drawn
    When I manually: use Redraw zone
    Then I confirm: the zone is redrawn
    When I manually: use Clear zone
    Then I confirm: the zone is cleared
    When I manually: stand outside the zone and try to use the shop as a customer
    Then I confirm: I cannot use the shop outside the zone
    When I manually: stand inside the zone and try to use the shop
    Then I confirm: I can use the shop inside the zone

  @kora_dealership @checklist @checklist:kora_dealership:creator-vehicles @cat:vehicles @needs:admin
  Scenario: Add vehicles and set prices
    """
    Checklist test: Vehicle Management: Add Vehicles with price, edit sale price (Save Price), duplicate vehicle rejected.
    """
    When I manually: run /dealershipcreator
    Then the "qbdealership:creator" app should be open
    When I manually: open a dealership and go to Vehicle Management
    And I manually: click Add Vehicles and add a vehicle with a price
    Then I confirm: the vehicle appears in the list with its price
    When I manually: edit the sale price and click Save Price
    Then I confirm: the new price is saved
    When I manually: try to add the same vehicle again
    Then I confirm: the duplicate vehicle is rejected

  @kora_dealership @checklist @checklist:kora_dealership:creator-displays-spawns @cat:vehicles @needs:admin
  Scenario: Place display vehicles and spawn points
    """
    Checklist test: Place a display vehicle and Add a spawn point by aiming; they appear in current lists and can be deleted.
    """
    When I manually: run /dealershipcreator
    Then the "qbdealership:creator" app should be open
    When I manually: open a dealership
    And I manually: place a display vehicle by aiming
    And I manually: add a spawn point by aiming
    Then I confirm: the display vehicle and spawn point appear in the current lists
    When I manually: delete the display vehicle and the spawn point
    Then I confirm: both entries are removed from the lists

  @kora_dealership @checklist @checklist:kora_dealership:creator-zones @cat:vehicles @needs:admin
  Scenario: Add management and sales zones
    """
    Checklist test: Dealer Management / Sales Zones: add management and sale zones by aiming; entries listed and removable.
    """
    When I manually: run /dealershipcreator
    Then the "qbdealership:creator" app should be open
    When I manually: open Dealer Management / Sales Zones
    And I manually: add a management zone by aiming
    And I manually: add a sale zone by aiming
    Then I confirm: both entries are listed
    When I manually: remove both zones
    Then I confirm: both entries are removed from the list

  @kora_dealership @checklist @checklist:kora_dealership:creator-delete @cat:vehicles @needs:admin
  Scenario: Delete dealership
    """
    Checklist test: Danger Zone > Delete dealership; confirmation dialog, then it is removed.
    """
    When I manually: run /dealershipcreator
    Then the "qbdealership:creator" app should be open
    When I manually: open a test dealership and go to Danger Zone
    And I manually: click Delete dealership
    Then I confirm: a confirmation dialog appears saying 'Are you sure you want to delete this dealership? This action cannot be undone.'
    When I manually: confirm the deletion
    Then I confirm: the dealership is removed from the list

  @kora_dealership @checklist @checklist:kora_dealership:pdm-seeded @cat:vehicles @needs:admin @manual
  Scenario: Default public PDM dealership
    """
    Checklist test: With Config.UsePDM, a fully set up public 'pdm' dealership exists on a fresh DB with display cars.
    """
    When I manually: run /dealershipcreator and look at the dealership list
    Then I confirm: a public 'pdm' dealership is listed (only applies when Config.UsePDM is enabled; otherwise mark Pass if nothing exists)
    When I manually: go to the pdm dealership
    Then I confirm: display cars are present at the pdm dealership

  @kora_dealership @checklist @checklist:kora_dealership:browse-showroom @cat:vehicles
  Scenario: Browse dealership via target
    """
    Checklist test: Target a display vehicle ('Browse dealership'); menu lists vehicles by class with search ('Type to search vehicles').
    """
    When I manually: go to a public dealership and look at a display vehicle
    And I select the "Browse dealership" target option
    Then the "qbdealership:showroom" app opens
    And I confirm: the menu lists vehicles grouped by class
    When I manually: type in the search field 'Type to search vehicles'
    Then I confirm: the vehicle list is filtered by my search

  @kora_dealership @checklist @checklist:kora_dealership:swap-display @cat:vehicles
  Scenario: Swap display vehicle
    """
    Checklist test: In browse menu click Swap on a vehicle; display car changes (1s cooldown, within 6m); 'Reset display to default' reverts.
    """
    When I manually: go to a public dealership and look at a display vehicle
    And I select the "Browse dealership" target option
    And I manually: click Swap on a vehicle
    Then I confirm: the display car changes to the chosen vehicle
    When I manually: click Swap again repeatedly within 1 second
    Then I confirm: swaps within the 1 second cooldown are refused
    When I manually: move more than 6m away from the display and try to swap
    Then I confirm: the swap is refused when I am too far away
    When I manually: click Reset display to default
    Then I confirm: the display car reverts to the default

  @kora_dealership @checklist @checklist:kora_dealership:test-drive @cat:vehicles
  Scenario: Test drive
    """
    Checklist test: Click Test drive; vehicle spawns in a private bucket, auto-ends after 120s or when you leave it.
    """
    When I manually: go to a public dealership and look at a display vehicle
    And I select the "Browse dealership" target option
    And I manually: click Test drive on a vehicle
    Then I should be in a vehicle
    And I should be in the driver seat
    And I confirm: the vehicle spawned in a private bucket (no other players visible)
    When I get out of the vehicle
    Then I confirm: the test drive ends and the vehicle is removed
    When I manually: start another test drive and stay in the vehicle
    And I wait 120 seconds
    Then I confirm: the test drive ended automatically after 120 seconds

  @kora_dealership @checklist @checklist:kora_dealership:purchase-vehicle @cat:vehicles
  Scenario: Purchase a vehicle
    """
    Checklist test: Click Purchase on a public dealership car; money is taken, vehicle spawns at a free spawn point and keys are given.
    """
    Given my cash balance is at least 100000
    When I manually: go to a public dealership and look at a display vehicle
    And I select the "Browse dealership" target option
    And I manually: click Purchase on a car and confirm
    Then I should see a notification containing "Purchase successful!"
    And I confirm: money was taken for the price of the car
    And I confirm: the vehicle spawns at a free spawn point
    And I confirm: I received the keys for the vehicle

  @kora_dealership @checklist @checklist:kora_dealership:purchase-funds @cat:vehicles
  Scenario: Insufficient funds on purchase
    """
    Checklist test: Try to buy a car you cannot afford; error shown, nothing spawned or charged.
    """
    Given my cash balance is 0
    And my bank balance is 0
    When I manually: go to a public dealership and look at a display vehicle
    And I select the "Browse dealership" target option
    And I manually: click Purchase on a car I cannot afford
    Then I should see an error notification
    And my cash balance should have changed by 0
    And my bank balance should have changed by 0
    And I confirm: no vehicle spawned

  @kora_dealership @checklist @checklist:kora_dealership:make-offer @cat:vehicles
  Scenario: Make an offer on owned dealership stock
    """
    Checklist test: On owned dealership click Make offer: Step 1 amount, Step 2 terms, Submit; max 5 pending offers per player.
    """
    When I manually: go to an owned dealership showroom
    And I manually: click Make offer on a vehicle
    Then the "qbdealership:offer-amount" app opens
    And I confirm: Step 1 asks for an offer amount
    When I manually: enter an amount and continue
    Then the "qbdealership:offer-terms" app opens
    And I confirm: Step 2 shows the terms
    When I manually: submit the offer
    Then I should see a notification containing "Your offer was sent."
    When I manually: submit offers until I have 5 pending offers, then try a sixth
    Then I confirm: the sixth offer is refused because the maximum of 5 pending offers is reached

  @kora_dealership @checklist @checklist:kora_dealership:management-portal @cat:vehicles
  Scenario: Owner management portal
    """
    Checklist test: Target management point 'Open Dealer Management' as owner or employee; sections shown depend on permissions.
    """
    When I manually: go to an owned dealership management point as its owner or an employee
    And I select the "Open Dealer Management" target option
    Then the "qbdealership:management" app opens
    And I confirm: the sections shown match the permissions of my role

  @kora_dealership @checklist @checklist:kora_dealership:employees @cat:vehicles
  Scenario: Hire and fire employees
    """
    Checklist test: Employee Management: add by server ID, see Current employees, Remove employee with confirmation.
    """
    When I manually: open Dealer Management as owner and go to Employee Management
    Then the "qbdealership:management" app should be open
    When I manually: add an employee by entering a second player's server ID
    Then I confirm: the new employee appears under Current employees
    When I manually: click Remove employee on that employee
    Then I confirm: a confirmation is requested
    When I manually: confirm the removal
    Then I confirm: the employee is removed from Current employees

  @kora_dealership @checklist @checklist:kora_dealership:employee-permissions @cat:vehicles
  Scenario: Employee permissions toggles
    """
    Checklist test: Permissions: toggle Sell vehicles, Handle offers, Order vehicles, Manage display; employee without access sees 'no access'.
    """
    When I manually: open Dealer Management as owner and go to Permissions for an employee
    Then the "qbdealership:management" app should be open
    When I manually: toggle Sell vehicles, Handle offers, Order vehicles and Manage display and save
    Then I confirm: each toggle state is saved
    When I manually: ask the employee to open Dealer Management and visit a section whose permission is off
    Then I confirm: the employee sees a 'no access' message for that section

  @kora_dealership @checklist @checklist:kora_dealership:funds @cat:vehicles
  Scenario: Deposit/withdraw dealership funds
    """
    Checklist test: Funds page: shows balance, income, spent; Deposit funds from your bank and Withdraw funds to bank.
    """
    When I manually: open Dealer Management as owner and go to the Funds page
    Then the "qbdealership:management" app should be open
    And I confirm: the Funds page shows balance, income and spent
    When I manually: deposit funds from my bank
    Then I confirm: the dealership balance increases and my bank balance decreases by the same amount
    When I manually: withdraw funds to my bank
    Then I confirm: the dealership balance decreases and my bank balance increases by the same amount

  @kora_dealership @checklist @checklist:kora_dealership:order-stock @cat:vehicles
  Scenario: Order vehicles for stock
    """
    Checklist test: Order vehicles page: pick vehicle and quantity (max 10); paid at 70% wholesale from dealership funds, stock increases.
    """
    When I manually: open Dealer Management as owner or employee and go to Order vehicles
    Then the "qbdealership:management" app should be open
    When I manually: pick a vehicle and try a quantity above 10
    Then I confirm: the quantity cannot exceed 10
    When I manually: submit an order with a quantity of 10 or less
    Then I confirm: the dealership funds drop by 70% of the listed price per vehicle ordered
    And I confirm: the stock of that vehicle increases by the ordered quantity

  @kora_dealership @checklist @checklist:kora_dealership:business-settings @cat:vehicles
  Scenario: Business settings
    """
    Checklist test: Settings: max price override %, commission %, employee discount %; Save settings.
    """
    When I manually: open Dealer Management as owner and go to Settings
    Then the "qbdealership:management" app should be open
    When I manually: set max price override %, commission % and employee discount % and click Save settings
    Then I confirm: a success confirmation is shown
    When I manually: reopen Settings
    Then I confirm: the saved values are shown

  @kora_dealership @checklist @checklist:kora_dealership:offers-manage @cat:vehicles
  Scenario: Accept or deny customer offers
    """
    Checklist test: Offers page: pending and history lists; Accept (vehicle delivered to customer garage, funds credited) or Deny with confirmation.
    """
    When I manually: open Dealer Management as owner or employee and go to the Offers page
    Then the "qbdealership:management" app should be open
    And I confirm: the pending and history lists are shown
    When I manually: accept a pending offer
    Then I confirm: the vehicle is delivered to the customer's garage
    And I confirm: the dealership funds are credited
    When I manually: click Deny on another pending offer
    Then I confirm: a confirmation is requested
    When I manually: confirm the denial
    Then I confirm: the offer moves to the history list as denied

  @kora_dealership @checklist @checklist:kora_dealership:sales-menu @cat:vehicles
  Scenario: Staff sales menu
    """
    Checklist test: Target sale zone 'Open Sales Menu': pick nearby customer, vehicle, price in allowed range, Offer to customer.
    """
    When I manually: go to an owned dealership sale zone with a second player standing nearby
    And I select the "Open Sales Menu" target option
    Then the "qbdealership:sales" app opens
    When I manually: pick the nearby customer and a vehicle
    And I manually: enter a price within the allowed range and click Offer to customer
    Then I confirm: the offer is sent to the customer

  @kora_dealership @checklist @checklist:kora_dealership:customer-accepts-sale @cat:vehicles @manual
  Scenario: Customer pays staff-initiated sale
    """
    Checklist test: Customer receives prompt 'X is offering to sell you this vehicle', chooses Cash or Card, pays; staff gets commission.
    """
    When I manually: ask a second player to wait nearby as the customer while I start a sale from the sales menu
    Then I confirm: the other player sees the prompt 'X is offering to sell you this vehicle'
    When I manually: ask the second player to choose Cash or Card and pay
    Then I confirm: the other player receives the vehicle
    And I confirm: I receive my commission

  @kora_dealership @checklist @checklist:kora_dealership:owned-stock-finite @cat:vehicles @manual
  Scenario: Owned dealership stock is finite
    """
    Checklist test: Buy until a vehicle's stock hits 0 at an owned dealership; further purchases blocked, public dealerships stay unlimited.
    """
    When I manually: buy a vehicle at an owned dealership until its stock reaches 0
    Then I confirm: further purchases of that vehicle are blocked
    When I manually: buy the same vehicle repeatedly at a public dealership
    Then I confirm: the public dealership stock never runs out

  @kora_dealership @checklist @checklist:kora_dealership:purchase-event @cat:vehicles
  Scenario: qb-vehicleshop purchase event
    """
    Checklist test: After purchase the server event qb-vehicleshop:server:onVehiclePurchased(citizenid, model, plate) fires (other resources react).
    """
    When I manually: ask a Mod to watch the server console for qb-vehicleshop:server:onVehiclePurchased (for example with a listener added by a dev)
    And I manually: go to a public dealership and buy a vehicle
    Then I should see a notification containing "Purchase successful!"
    And I confirm: the Mod saw qb-vehicleshop:server:onVehiclePurchased fire once with my citizenid, the model and the plate of the vehicle I bought
    And I confirm: any other resource that reacts to a vehicle purchase responded for the bought vehicle
