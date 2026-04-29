//
//  BarcodeScannerView.swift
//  mercantis core
//
//  W9: AVFoundation-based scanner. iOS only. (ADR-035)
//

#if os(iOS)
import SwiftUI
import AVFoundation
import UIKit

public struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    public init(onScan: @escaping (String) -> Void) {
        self.onScan = onScan
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    public func makeUIViewController(context: Context) -> ScannerVC {
        ScannerVC(coordinator: context.coordinator)
    }

    public func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}

    public final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        public func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let str = obj.stringValue else { return }
            onScan(str)
        }
    }

    public final class ScannerVC: UIViewController {
        private let session = AVCaptureSession()
        private let coordinator: Coordinator

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported for BarcodeScannerView.ScannerVC")
        }

        public override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .qr, .code128, .code39, .upce, .pdf417]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.layer.bounds
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)

            DispatchQueue.global(qos: .userInitiated).async { [session] in
                session.startRunning()
            }
        }

        public override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }
    }
}
#endif
