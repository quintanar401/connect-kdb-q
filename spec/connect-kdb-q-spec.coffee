ConnectKdbQ = require '../lib/connect-kdb-q'

# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "ConnectKdbQ", ->
  [workspaceElement, activationPromise] = []

  beforeEach ->
    workspaceElement = atom.views.getView(atom.workspace)
    activationPromise = atom.packages.activatePackage('connect-kdb-q')

  describe "when the connect-kdb-q:toggle event is triggered", ->
    it "hides and shows the modal panel", ->
      # Before the activation event the view is not on the DOM, and no panel
      # has been created
      expect(workspaceElement.querySelector('.connect-kdb-q')).not.toExist()

      # This is an activation event, triggering it will cause the package to be
      # activated.
      atom.commands.dispatch workspaceElement, 'connect-kdb-q:toggle'

      waitsForPromise ->
        activationPromise

      runs ->
        expect(workspaceElement.querySelector('.connect-kdb-q')).toExist()

        connectKdbQElement = workspaceElement.querySelector('.connect-kdb-q')
        expect(connectKdbQElement).toExist()

        connectKdbQPanel = atom.workspace.panelForItem(connectKdbQElement)
        expect(connectKdbQPanel.isVisible()).toBe true
        atom.commands.dispatch workspaceElement, 'connect-kdb-q:toggle'
        expect(connectKdbQPanel.isVisible()).toBe false

    it "hides and shows the view", ->
      # This test shows you an integration test testing at the view level.

      # Attaching the workspaceElement to the DOM is required to allow the
      # `toBeVisible()` matchers to work. Anything testing visibility or focus
      # requires that the workspaceElement is on the DOM. Tests that attach the
      # workspaceElement to the DOM are generally slower than those off DOM.
      jasmine.attachToDOM(workspaceElement)

      expect(workspaceElement.querySelector('.connect-kdb-q')).not.toExist()

      # This is an activation event, triggering it causes the package to be
      # activated.
      atom.commands.dispatch workspaceElement, 'connect-kdb-q:toggle'

      waitsForPromise ->
        activationPromise

      runs ->
        # Now we can test for view visibility
        connectKdbQElement = workspaceElement.querySelector('.connect-kdb-q')
        expect(connectKdbQElement).toBeVisible()
        atom.commands.dispatch workspaceElement, 'connect-kdb-q:toggle'
        expect(connectKdbQElement).not.toBeVisible()
