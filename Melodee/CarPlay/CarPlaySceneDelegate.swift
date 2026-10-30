import CarPlay
import UIKit

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var controller: CarPlayController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        // CarPlay can launch the app without the phone UI, so make sure the shared state is ready
        AppServices.shared.start()
        let controller = CarPlayController(interfaceController: interfaceController,
                                           services: AppServices.shared)
        controller.connect()
        self.controller = controller
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        controller?.disconnect()
        controller = nil
    }
}
