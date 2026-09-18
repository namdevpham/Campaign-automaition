// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "EthopexWorkspace",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "EthopexWorkspace",
            targets: ["EthopexWorkspace"]
        )
    ],
    targets: [
        .executableTarget(
            name: "EthopexWorkspace",
            path: ".",
            exclude: [
                ".github",
                ".gitignore",
                "Info.plist",
                "README.md",
                "README_VI.md",
                "UPDATE_PACKAGE_FORMAT.md",
                "V1_7_0_TEMPLATE_VALIDATION.txt",
                "build.command",
                "build.yml",
                "NAM_QUIZ_MASTER_RULES.md"
            ],
            resources: [
                .copy("NAM_QUIZ_MASTER_RULES.md")
            ]
        )
    ]
)
