// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cloudpayments_sdk",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "cloudpayments-sdk", targets: ["cloudpayments_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(
            url: "https://gitpub.cloudpayments.ru/integrations/sdk/cloudpayments-ios.git",
            exact: "2.1.6"
        ),
    ],
    targets: [
        .target(
            name: "cloudpayments_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "Cloudpayments", package: "cloudpayments-ios"),
            ]
        )
    ]
)
