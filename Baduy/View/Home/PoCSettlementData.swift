import Foundation
import CoreLocation
import RealityKit
import UIKit

/// Spatial representation of surrounding village buildings (settlement cluster)
struct SettlementBuilding: Identifiable {
    let id: String
    let position: SIMD3<Float>
    let size: SIMD3<Float>
    let rotationY: Float
    let kind: BuildingKind

    enum BuildingKind {
        case residentialStiltHouse // Rumah panggung adat Sunda/Baduy
        case granaryLeuit          // Lumbung padi tradisional (Leuit)
        case communityGazebo       // Saung / bale musyawarah
    }
}

enum SettlementData {
    /// ALL 214 REAL building footprints converted directly from GeoJSON across the full expanded territory
    static let surroundingBuildings: [SettlementBuilding] = [
        .init(id: "b_1467566321", position: [-430.4, 0, 484.8], size: [6.7, 3.2, 5.5], rotationY: -0.0, kind: .residentialStiltHouse),
        .init(id: "b_1467566322", position: [-438.6, 0, 497.2], size: [9.8, 3.2, 9.1], rotationY: -0.08, kind: .communityGazebo),
        .init(id: "b_1467567421", position: [87.3, 0, 542.9], size: [5.9, 3.2, 4.1], rotationY: 0.41, kind: .granaryLeuit),
        .init(id: "b_1467567422", position: [58.1, 0, 637.0], size: [15.2, 3.2, 15.9], rotationY: -0.47, kind: .communityGazebo),
        .init(id: "b_1467567423", position: [52.3, 0, 634.8], size: [4.0, 3.2, 4.0], rotationY: 0.19, kind: .granaryLeuit),
        .init(id: "b_1467567424", position: [16.3, 0, 645.2], size: [9.3, 3.2, 10.2], rotationY: -0.39, kind: .communityGazebo),
        .init(id: "b_1467567425", position: [70.4, 0, 688.7], size: [5.8, 3.2, 5.9], rotationY: -0.37, kind: .residentialStiltHouse),
        .init(id: "b_1467567426", position: [78.4, 0, 730.2], size: [4.3, 3.2, 4.3], rotationY: 0.25, kind: .granaryLeuit),
        .init(id: "b_1467567427", position: [64.5, 0, 664.0], size: [10.4, 3.2, 12.6], rotationY: -0.37, kind: .communityGazebo),
        .init(id: "b_1467567428", position: [37.0, 0, 676.0], size: [12.9, 3.2, 12.3], rotationY: -0.45, kind: .communityGazebo),
        .init(id: "b_1467567429", position: [38.7, 0, 686.5], size: [17.8, 3.2, 15.9], rotationY: -0.05, kind: .communityGazebo),
        .init(id: "b_1467567430", position: [5.6, 0, 706.6], size: [10.3, 3.2, 10.5], rotationY: -0.2, kind: .communityGazebo),
        .init(id: "b_1467567573", position: [260.5, 0, 243.7], size: [5.9, 3.2, 7.4], rotationY: -0.14, kind: .residentialStiltHouse),
        .init(id: "b_1467567576", position: [152.1, 0, 69.1], size: [12.6, 3.2, 5.8], rotationY: 0.33, kind: .residentialStiltHouse),
        .init(id: "b_1467567577", position: [82.5, 0, 73.2], size: [13.8, 3.2, 12.7], rotationY: -0.17, kind: .communityGazebo),
        .init(id: "b_1467567578", position: [70.6, 0, 70.0], size: [5.8, 3.2, 5.8], rotationY: 0.14, kind: .residentialStiltHouse),
        .init(id: "b_1467567579", position: [23.3, 0, 153.1], size: [7.4, 3.2, 7.1], rotationY: 0.04, kind: .residentialStiltHouse),
        .init(id: "b_1467567580", position: [3.6, 0, 244.1], size: [5.8, 3.2, 4.9], rotationY: -0.42, kind: .residentialStiltHouse),
        .init(id: "b_1467567581", position: [-19.7, 0, 280.3], size: [6.1, 3.2, 6.7], rotationY: 0.44, kind: .residentialStiltHouse),
        .init(id: "b_1467570199", position: [135.9, 0, 72.5], size: [8.8, 3.2, 7.7], rotationY: -0.44, kind: .residentialStiltHouse),
        .init(id: "b_1467571944", position: [97.2, 0, 738.9], size: [9.5, 3.2, 9.5], rotationY: 0.48, kind: .communityGazebo),
        .init(id: "b_1467571945", position: [96.1, 0, 696.7], size: [4.9, 3.2, 4.8], rotationY: 0.22, kind: .granaryLeuit),
        .init(id: "b_1467571946", position: [88.1, 0, 694.5], size: [4.0, 3.2, 4.0], rotationY: -0.29, kind: .granaryLeuit),
        .init(id: "b_1467571947", position: [91.7, 0, 694.4], size: [5.2, 3.2, 5.1], rotationY: -0.09, kind: .residentialStiltHouse),
        .init(id: "b_1467571948", position: [103.8, 0, 697.7], size: [4.5, 3.2, 4.5], rotationY: -0.39, kind: .granaryLeuit),
        .init(id: "b_1467571949", position: [105.2, 0, 694.4], size: [5.5, 3.2, 5.6], rotationY: -0.41, kind: .residentialStiltHouse),
        .init(id: "b_1467571950", position: [102.9, 0, 691.3], size: [5.7, 3.2, 5.8], rotationY: 0.42, kind: .residentialStiltHouse),
        .init(id: "b_1467571951", position: [99.5, 0, 692.8], size: [5.3, 3.2, 5.3], rotationY: 0.28, kind: .residentialStiltHouse),
        .init(id: "b_1467571952", position: [96.4, 0, 689.2], size: [5.1, 3.2, 5.2], rotationY: 0.01, kind: .residentialStiltHouse),
        .init(id: "b_1467571953", position: [99.0, 0, 687.4], size: [4.8, 3.2, 5.0], rotationY: 0.1, kind: .granaryLeuit),
        .init(id: "b_1467571954", position: [95.5, 0, 684.1], size: [4.9, 3.2, 4.9], rotationY: -0.19, kind: .granaryLeuit),
        .init(id: "b_1467571955", position: [92.2, 0, 686.5], size: [5.4, 3.2, 5.3], rotationY: -0.3, kind: .residentialStiltHouse),
        .init(id: "b_1467571956", position: [113.1, 0, 705.3], size: [13.1, 3.2, 13.6], rotationY: 0.34, kind: .communityGazebo),
        .init(id: "b_1467571957", position: [118.1, 0, 710.4], size: [12.0, 3.2, 12.3], rotationY: -0.28, kind: .communityGazebo),
        .init(id: "b_1467571958", position: [121.6, 0, 714.8], size: [9.0, 3.2, 9.1], rotationY: 0.04, kind: .communityGazebo),
        .init(id: "b_1467571959", position: [129.2, 0, 719.0], size: [14.3, 3.2, 15.2], rotationY: -0.47, kind: .communityGazebo),
        .init(id: "b_1467571964", position: [37.6, 0, 591.5], size: [9.1, 3.2, 14.4], rotationY: 0.21, kind: .communityGazebo),
        .init(id: "b_1467571965", position: [46.9, 0, 586.8], size: [7.5, 3.2, 8.5], rotationY: -0.47, kind: .residentialStiltHouse),
        .init(id: "b_1467571966", position: [25.4, 0, 795.2], size: [4.1, 3.2, 4.6], rotationY: 0.36, kind: .granaryLeuit),
        .init(id: "b_1467571967", position: [28.9, 0, 798.2], size: [4.0, 3.2, 4.5], rotationY: -0.41, kind: .granaryLeuit),
        .init(id: "b_1467571968", position: [29.5, 0, 794.6], size: [4.2, 3.2, 4.1], rotationY: -0.48, kind: .granaryLeuit),
        .init(id: "b_1467571969", position: [42.1, 0, 791.6], size: [4.2, 3.2, 4.0], rotationY: 0.11, kind: .granaryLeuit),
        .init(id: "b_1467571970", position: [37.9, 0, 801.6], size: [4.0, 3.2, 4.0], rotationY: 0.18, kind: .granaryLeuit),
        .init(id: "b_1467571971", position: [37.9, 0, 797.9], size: [4.0, 3.2, 4.0], rotationY: 0.07, kind: .granaryLeuit),
        .init(id: "b_1467571972", position: [0.2, 0, 775.7], size: [4.6, 3.2, 4.1], rotationY: 0.51, kind: .granaryLeuit),
        .init(id: "b_1467571973", position: [-9.3, 0, 777.6], size: [4.1, 3.2, 4.0], rotationY: 0.05, kind: .granaryLeuit),
        .init(id: "b_1467571974", position: [-9.5, 0, 781.0], size: [4.2, 3.2, 4.0], rotationY: 0.14, kind: .granaryLeuit),
        .init(id: "b_1467571975", position: [-4.6, 0, 778.9], size: [4.5, 3.2, 4.6], rotationY: 0.35, kind: .granaryLeuit),
        .init(id: "b_1467571976", position: [-0.3, 0, 779.8], size: [5.1, 3.2, 5.2], rotationY: -0.44, kind: .residentialStiltHouse),
        .init(id: "b_1467571977", position: [8.6, 0, 781.2], size: [4.8, 3.2, 4.7], rotationY: 0.08, kind: .granaryLeuit),
        .init(id: "b_1467571978", position: [3.0, 0, 785.8], size: [4.5, 3.2, 5.3], rotationY: -0.08, kind: .granaryLeuit),
        .init(id: "b_1467571979", position: [4.5, 0, 778.1], size: [4.4, 3.2, 4.2], rotationY: -0.23, kind: .granaryLeuit),
        .init(id: "b_1467571980", position: [34.9, 0, 794.1], size: [5.4, 3.2, 4.0], rotationY: -0.21, kind: .granaryLeuit),
        .init(id: "b_1467571981", position: [65.1, 0, 742.9], size: [5.4, 3.2, 5.5], rotationY: -0.09, kind: .residentialStiltHouse),
        .init(id: "b_1467571982", position: [69.0, 0, 741.0], size: [5.3, 3.2, 5.5], rotationY: 0.06, kind: .residentialStiltHouse),
        .init(id: "b_1467571983", position: [71.3, 0, 738.2], size: [4.9, 3.2, 5.1], rotationY: 0.1, kind: .granaryLeuit),
        .init(id: "b_1467571984", position: [75.1, 0, 735.6], size: [5.1, 3.2, 5.5], rotationY: 0.24, kind: .residentialStiltHouse),
        .init(id: "b_1467571985", position: [79.0, 0, 734.4], size: [6.7, 3.2, 6.2], rotationY: 0.41, kind: .residentialStiltHouse),
        .init(id: "b_1467571986", position: [66.6, 0, 727.0], size: [15.5, 3.2, 14.7], rotationY: -0.48, kind: .communityGazebo),
        .init(id: "b_1467571987", position: [59.6, 0, 735.2], size: [12.5, 3.2, 11.0], rotationY: 0.43, kind: .communityGazebo),
        .init(id: "b_1467571988", position: [54.8, 0, 732.2], size: [12.2, 3.2, 10.6], rotationY: 0.08, kind: .communityGazebo),
        .init(id: "b_1467571989", position: [45.0, 0, 740.6], size: [12.5, 3.2, 11.4], rotationY: -0.2, kind: .communityGazebo),
        .init(id: "b_1467571990", position: [41.6, 0, 734.2], size: [14.2, 3.2, 12.6], rotationY: 0.47, kind: .communityGazebo),
        .init(id: "b_1467571991", position: [52.5, 0, 725.9], size: [13.4, 3.2, 11.9], rotationY: -0.23, kind: .communityGazebo),
        .init(id: "b_1467571992", position: [61.0, 0, 720.0], size: [14.4, 3.2, 13.0], rotationY: 0.06, kind: .communityGazebo),
        .init(id: "b_1467571993", position: [45.0, 0, 716.5], size: [15.0, 3.2, 12.2], rotationY: 0.13, kind: .communityGazebo),
        .init(id: "b_1467571994", position: [56.0, 0, 712.0], size: [15.4, 3.2, 13.6], rotationY: -0.45, kind: .communityGazebo),
        .init(id: "b_1467571995", position: [50.9, 0, 704.0], size: [17.4, 3.2, 15.2], rotationY: 0.08, kind: .communityGazebo),
        .init(id: "b_1467571996", position: [37.9, 0, 712.5], size: [14.7, 3.2, 12.6], rotationY: -0.37, kind: .communityGazebo),
        .init(id: "b_1467571997", position: [27.9, 0, 718.4], size: [12.9, 3.2, 11.6], rotationY: 0.31, kind: .communityGazebo),
        .init(id: "b_1467571998", position: [18.9, 0, 713.9], size: [14.4, 3.2, 12.2], rotationY: -0.31, kind: .communityGazebo),
        .init(id: "b_1467571999", position: [30.7, 0, 706.9], size: [12.9, 3.2, 11.0], rotationY: 0.12, kind: .communityGazebo),
        .init(id: "b_1467572000", position: [38.9, 0, 701.5], size: [12.9, 3.2, 11.1], rotationY: 0.41, kind: .communityGazebo),
        .init(id: "b_1467572001", position: [47.6, 0, 694.6], size: [14.4, 3.2, 13.0], rotationY: -0.37, kind: .communityGazebo),
        .init(id: "b_1467572002", position: [-5.9, 0, 661.1], size: [11.5, 3.2, 9.6], rotationY: -0.08, kind: .communityGazebo),
        .init(id: "b_1467572003", position: [-15.9, 0, 666.8], size: [13.3, 3.2, 10.8], rotationY: -0.45, kind: .communityGazebo),
        .init(id: "b_1467572004", position: [9.3, 0, 651.1], size: [13.4, 3.2, 12.6], rotationY: 0.45, kind: .communityGazebo),
        .init(id: "b_1467572005", position: [15.2, 0, 654.7], size: [12.8, 3.2, 11.9], rotationY: -0.17, kind: .communityGazebo),
        .init(id: "b_1467572006", position: [6.6, 0, 662.2], size: [13.3, 3.2, 11.7], rotationY: -0.42, kind: .communityGazebo),
        .init(id: "b_1467572007", position: [-2.4, 0, 668.9], size: [12.8, 3.2, 11.7], rotationY: 0.34, kind: .communityGazebo),
        .init(id: "b_1467572008", position: [12.4, 0, 692.5], size: [14.3, 3.2, 11.9], rotationY: -0.25, kind: .communityGazebo),
        .init(id: "b_1467572009", position: [-2.5, 0, 698.0], size: [14.1, 3.2, 11.9], rotationY: 0.15, kind: .communityGazebo),
        .init(id: "b_1467572010", position: [12.9, 0, 679.8], size: [13.5, 3.2, 12.1], rotationY: 0.45, kind: .communityGazebo),
        .init(id: "b_1467572011", position: [0.9, 0, 685.5], size: [13.4, 3.2, 11.6], rotationY: -0.04, kind: .communityGazebo),
        .init(id: "b_1467572012", position: [-10.1, 0, 691.9], size: [14.0, 3.2, 12.0], rotationY: -0.44, kind: .communityGazebo),
        .init(id: "b_1467572013", position: [-17.8, 0, 685.7], size: [12.5, 3.2, 11.6], rotationY: 0.01, kind: .communityGazebo),
        .init(id: "b_1467572014", position: [-6.9, 0, 681.0], size: [13.8, 3.2, 11.7], rotationY: 0.46, kind: .communityGazebo),
        .init(id: "b_1467572015", position: [2.6, 0, 674.1], size: [11.4, 3.2, 10.5], rotationY: -0.28, kind: .communityGazebo),
        .init(id: "b_1467572016", position: [10.3, 0, 669.3], size: [12.9, 3.2, 11.2], rotationY: -0.0, kind: .communityGazebo),
        .init(id: "b_1467572017", position: [21.3, 0, 663.3], size: [14.7, 3.2, 13.0], rotationY: 0.41, kind: .communityGazebo),
        .init(id: "b_1467572018", position: [24.6, 0, 671.4], size: [16.5, 3.2, 14.1], rotationY: -0.22, kind: .communityGazebo),
        .init(id: "b_1467572019", position: [26.3, 0, 693.4], size: [12.5, 3.2, 11.7], rotationY: -0.52, kind: .communityGazebo),
        .init(id: "b_1467572020", position: [24.0, 0, 683.8], size: [16.9, 3.2, 14.9], rotationY: 0.12, kind: .communityGazebo),
        .init(id: "b_1467572021", position: [56.7, 0, 677.6], size: [11.7, 3.2, 12.9], rotationY: -0.39, kind: .communityGazebo),
        .init(id: "b_1467572022", position: [48.4, 0, 668.8], size: [11.5, 3.2, 11.9], rotationY: -0.05, kind: .communityGazebo),
        .init(id: "b_1467572023", position: [38.1, 0, 653.9], size: [8.6, 3.2, 11.2], rotationY: -0.01, kind: .communityGazebo),
        .init(id: "b_1467572024", position: [41.7, 0, 661.0], size: [10.3, 3.2, 10.7], rotationY: 0.4, kind: .communityGazebo),
        .init(id: "b_1467572025", position: [29.8, 0, 634.4], size: [10.5, 3.2, 13.8], rotationY: 0.01, kind: .communityGazebo),
        .init(id: "b_1467572026", position: [27.5, 0, 646.0], size: [7.8, 3.2, 13.3], rotationY: 0.24, kind: .communityGazebo),
        .init(id: "b_1467572027", position: [36.5, 0, 642.0], size: [9.1, 3.2, 11.5], rotationY: -0.44, kind: .communityGazebo),
        .init(id: "b_1467572028", position: [43.3, 0, 645.3], size: [10.7, 3.2, 12.3], rotationY: 0.02, kind: .communityGazebo),
        .init(id: "b_1467572029", position: [49.6, 0, 649.7], size: [13.3, 3.2, 14.6], rotationY: 0.49, kind: .communityGazebo),
        .init(id: "b_1467572030", position: [53.7, 0, 656.6], size: [11.7, 3.2, 13.2], rotationY: -0.12, kind: .communityGazebo),
        .init(id: "b_1467572031", position: [57.8, 0, 660.8], size: [13.4, 3.2, 15.3], rotationY: 0.22, kind: .communityGazebo),
        .init(id: "b_1467572032", position: [70.7, 0, 669.0], size: [12.5, 3.2, 14.2], rotationY: 0.11, kind: .communityGazebo),
        .init(id: "b_1467572033", position: [83.8, 0, 721.9], size: [13.8, 3.2, 14.8], rotationY: 0.3, kind: .communityGazebo),
        .init(id: "b_1467572034", position: [77.3, 0, 714.9], size: [13.0, 3.2, 11.1], rotationY: -0.26, kind: .communityGazebo),
        .init(id: "b_1467572035", position: [71.4, 0, 706.4], size: [14.1, 3.2, 11.4], rotationY: 0.21, kind: .communityGazebo),
        .init(id: "b_1467572036", position: [70.0, 0, 697.4], size: [10.1, 3.2, 8.8], rotationY: -0.13, kind: .communityGazebo),
        .init(id: "b_1467572037", position: [131.8, 0, 681.4], size: [13.9, 3.2, 12.1], rotationY: -0.4, kind: .communityGazebo),
        .init(id: "b_1467572038", position: [137.2, 0, 684.9], size: [14.0, 3.2, 12.2], rotationY: -0.01, kind: .communityGazebo),
        .init(id: "b_1467572039", position: [151.5, 0, 684.4], size: [13.6, 3.2, 12.8], rotationY: -0.3, kind: .communityGazebo),
        .init(id: "b_1467572040", position: [146.6, 0, 678.3], size: [13.0, 3.2, 11.8], rotationY: 0.31, kind: .communityGazebo),
        .init(id: "b_1467572041", position: [140.6, 0, 674.4], size: [12.9, 3.2, 11.4], rotationY: -0.13, kind: .communityGazebo),
        .init(id: "b_1467572042", position: [135.0, 0, 669.7], size: [12.8, 3.2, 11.3], rotationY: 0.47, kind: .communityGazebo),
        .init(id: "b_1467572043", position: [125.7, 0, 675.6], size: [13.9, 3.2, 11.5], rotationY: 0.14, kind: .communityGazebo),
        .init(id: "b_1467572044", position: [127.7, 0, 658.3], size: [12.2, 3.2, 10.3], rotationY: -0.26, kind: .communityGazebo),
        .init(id: "b_1467572045", position: [131.1, 0, 664.9], size: [17.9, 3.2, 14.0], rotationY: 0.12, kind: .communityGazebo),
        .init(id: "b_1467572046", position: [116.5, 0, 672.4], size: [12.3, 3.2, 10.4], rotationY: -0.45, kind: .communityGazebo),
        .init(id: "b_1467572047", position: [97.4, 0, 672.4], size: [12.7, 3.2, 11.7], rotationY: -0.44, kind: .communityGazebo),
        .init(id: "b_1467572048", position: [92.1, 0, 665.7], size: [14.1, 3.2, 13.4], rotationY: 0.13, kind: .communityGazebo),
        .init(id: "b_1467572049", position: [112.6, 0, 659.0], size: [12.2, 3.2, 9.1], rotationY: -0.01, kind: .communityGazebo),
        .init(id: "b_1467572050", position: [89.6, 0, 647.9], size: [13.0, 3.2, 11.7], rotationY: 0.51, kind: .communityGazebo),
        .init(id: "b_1467572051", position: [84.7, 0, 659.7], size: [14.0, 3.2, 14.3], rotationY: -0.45, kind: .communityGazebo),
        .init(id: "b_1467572052", position: [78.5, 0, 655.5], size: [13.7, 3.2, 15.1], rotationY: 0.13, kind: .communityGazebo),
        .init(id: "b_1467572053", position: [73.5, 0, 648.8], size: [14.1, 3.2, 14.9], rotationY: -0.33, kind: .communityGazebo),
        .init(id: "b_1467572054", position: [67.8, 0, 642.7], size: [12.5, 3.2, 14.3], rotationY: 0.22, kind: .communityGazebo),
        .init(id: "b_1467572167", position: [64.3, 0, 576.3], size: [9.0, 3.2, 12.2], rotationY: 0.15, kind: .communityGazebo),
        .init(id: "b_1467572168", position: [57.8, 0, 588.0], size: [13.8, 3.2, 9.6], rotationY: 0.15, kind: .communityGazebo),
        .init(id: "b_1467572169", position: [35.2, 0, 565.8], size: [7.2, 3.2, 14.3], rotationY: 0.37, kind: .communityGazebo),
        .init(id: "b_1467572170", position: [35.2, 0, 576.3], size: [7.9, 3.2, 13.0], rotationY: -0.37, kind: .communityGazebo),
        .init(id: "b_1467572171", position: [44.6, 0, 575.8], size: [8.3, 3.2, 13.1], rotationY: 0.13, kind: .communityGazebo),
        .init(id: "b_1467572172", position: [45.5, 0, 566.0], size: [7.1, 3.2, 13.8], rotationY: -0.12, kind: .communityGazebo),
        .init(id: "b_1467572173", position: [54.6, 0, 562.7], size: [7.0, 3.2, 13.2], rotationY: 0.28, kind: .communityGazebo),
        .init(id: "b_1467572174", position: [54.4, 0, 574.7], size: [7.7, 3.2, 13.6], rotationY: -0.42, kind: .communityGazebo),
        .init(id: "b_1467572175", position: [145.0, 0, 510.6], size: [5.5, 3.2, 5.6], rotationY: 0.48, kind: .residentialStiltHouse),
        .init(id: "b_1467572176", position: [109.2, 0, 544.0], size: [5.4, 3.2, 5.6], rotationY: -0.47, kind: .residentialStiltHouse),
        .init(id: "b_1467572177", position: [88.2, 0, 567.6], size: [6.2, 3.2, 4.0], rotationY: 0.15, kind: .granaryLeuit),
        .init(id: "b_1467572178", position: [119.8, 0, 563.2], size: [5.0, 3.2, 4.6], rotationY: -0.37, kind: .granaryLeuit),
        .init(id: "b_1467572179", position: [109.2, 0, 568.2], size: [7.6, 3.2, 10.9], rotationY: 0.25, kind: .communityGazebo),
        .init(id: "b_1467572180", position: [78.1, 0, 575.7], size: [6.8, 3.2, 10.8], rotationY: -0.16, kind: .residentialStiltHouse),
        .init(id: "b_1467572181", position: [86.6, 0, 576.5], size: [13.2, 3.2, 9.3], rotationY: 0.32, kind: .communityGazebo),
        .init(id: "b_1467572182", position: [89.9, 0, 596.6], size: [4.0, 3.2, 4.4], rotationY: 0.05, kind: .granaryLeuit),
        .init(id: "b_1467572183", position: [92.4, 0, 584.2], size: [5.2, 3.2, 5.0], rotationY: -0.19, kind: .residentialStiltHouse),
        .init(id: "b_1467572184", position: [93.0, 0, 588.9], size: [4.0, 3.2, 4.0], rotationY: -0.01, kind: .granaryLeuit),
        .init(id: "b_1467572185", position: [92.5, 0, 592.6], size: [4.7, 3.2, 4.5], rotationY: 0.07, kind: .granaryLeuit),
        .init(id: "b_1467572186", position: [94.8, 0, 598.6], size: [5.5, 3.2, 5.4], rotationY: 0.38, kind: .residentialStiltHouse),
        .init(id: "b_1467572187", position: [105.7, 0, 589.6], size: [6.0, 3.2, 6.0], rotationY: -0.35, kind: .residentialStiltHouse),
        .init(id: "b_1467572188", position: [98.5, 0, 594.9], size: [6.2, 3.2, 6.4], rotationY: 0.47, kind: .residentialStiltHouse),
        .init(id: "b_1467572189", position: [103.0, 0, 582.4], size: [4.2, 3.2, 4.3], rotationY: 0.34, kind: .granaryLeuit),
        .init(id: "b_1467572190", position: [132.2, 0, 561.1], size: [4.0, 3.2, 4.0], rotationY: 0.24, kind: .granaryLeuit),
        .init(id: "b_1467572191", position: [116.5, 0, 574.5], size: [4.5, 3.2, 4.8], rotationY: -0.21, kind: .granaryLeuit),
        .init(id: "b_1467572192", position: [123.8, 0, 570.9], size: [4.8, 3.2, 5.3], rotationY: 0.08, kind: .residentialStiltHouse),
        .init(id: "b_1467572193", position: [120.2, 0, 573.1], size: [5.2, 3.2, 5.4], rotationY: -0.06, kind: .residentialStiltHouse),
        .init(id: "b_1467572194", position: [118.0, 0, 569.1], size: [5.1, 3.2, 4.9], rotationY: -0.29, kind: .granaryLeuit),
        .init(id: "b_1467572195", position: [126.3, 0, 567.4], size: [5.1, 3.2, 5.2], rotationY: 0.11, kind: .residentialStiltHouse),
        .init(id: "b_1467572196", position: [129.0, 0, 563.1], size: [5.0, 3.2, 4.9], rotationY: 0.12, kind: .granaryLeuit),
        .init(id: "b_1467572197", position: [133.0, 0, 549.0], size: [4.0, 3.2, 4.0], rotationY: -0.08, kind: .granaryLeuit),
        .init(id: "b_1467572198", position: [126.6, 0, 554.5], size: [8.4, 3.2, 11.3], rotationY: -0.26, kind: .communityGazebo),
        .init(id: "b_1467572199", position: [124.2, 0, 547.1], size: [8.8, 3.2, 7.1], rotationY: 0.44, kind: .residentialStiltHouse),
        .init(id: "b_1467572200", position: [137.7, 0, 536.7], size: [8.7, 3.2, 11.1], rotationY: -0.19, kind: .communityGazebo),
        .init(id: "b_1467572201", position: [121.6, 0, 535.0], size: [9.6, 3.2, 6.5], rotationY: -0.06, kind: .residentialStiltHouse),
        .init(id: "b_1467572202", position: [127.6, 0, 526.8], size: [7.9, 3.2, 11.4], rotationY: 0.02, kind: .communityGazebo),
        .init(id: "b_1467572203", position: [134.7, 0, 526.1], size: [6.8, 3.2, 9.9], rotationY: 0.39, kind: .residentialStiltHouse),
        .init(id: "b_1467572204", position: [141.0, 0, 528.8], size: [6.8, 3.2, 5.2], rotationY: -0.24, kind: .residentialStiltHouse),
        .init(id: "b_1467572205", position: [142.8, 0, 522.4], size: [10.9, 3.2, 8.1], rotationY: -0.33, kind: .communityGazebo),
        .init(id: "b_1467572206", position: [144.6, 0, 515.8], size: [11.0, 3.2, 8.9], rotationY: -0.43, kind: .communityGazebo),
        .init(id: "b_1467572207", position: [135.1, 0, 516.7], size: [11.4, 3.2, 10.1], rotationY: 0.13, kind: .communityGazebo),
        .init(id: "b_1467572208", position: [135.7, 0, 510.4], size: [10.7, 3.2, 8.5], rotationY: -0.03, kind: .communityGazebo),
        .init(id: "b_1467572209", position: [123.1, 0, 511.9], size: [12.1, 3.2, 13.4], rotationY: 0.38, kind: .communityGazebo),
        .init(id: "b_1467572210", position: [66.0, 0, 558.6], size: [9.3, 3.2, 14.4], rotationY: -0.28, kind: .communityGazebo),
        .init(id: "b_1467572211", position: [78.6, 0, 562.3], size: [10.8, 3.2, 13.6], rotationY: 0.51, kind: .communityGazebo),
        .init(id: "b_1467572212", position: [89.5, 0, 560.3], size: [6.0, 3.2, 9.5], rotationY: -0.0, kind: .residentialStiltHouse),
        .init(id: "b_1467572213", position: [99.6, 0, 561.5], size: [8.6, 3.2, 13.6], rotationY: -0.47, kind: .communityGazebo),
        .init(id: "b_1467572214", position: [110.3, 0, 557.4], size: [10.6, 3.2, 7.1], rotationY: -0.01, kind: .residentialStiltHouse),
        .init(id: "b_1467572215", position: [97.9, 0, 551.1], size: [9.9, 3.2, 6.3], rotationY: 0.18, kind: .residentialStiltHouse),
        .init(id: "b_1467572216", position: [97.2, 0, 545.7], size: [10.0, 3.2, 6.7], rotationY: -0.02, kind: .residentialStiltHouse),
        .init(id: "b_1467572217", position: [75.3, 0, 547.8], size: [10.5, 3.2, 15.4], rotationY: -0.09, kind: .communityGazebo),
        .init(id: "b_1467572218", position: [109.5, 0, 518.7], size: [8.5, 3.2, 6.6], rotationY: -0.16, kind: .residentialStiltHouse),
        .init(id: "b_1467572219", position: [106.6, 0, 525.7], size: [9.1, 3.2, 10.0], rotationY: -0.1, kind: .communityGazebo),
        .init(id: "b_1467572220", position: [97.6, 0, 521.2], size: [10.5, 3.2, 13.8], rotationY: 0.32, kind: .communityGazebo),
        .init(id: "b_1467572221", position: [96.3, 0, 533.1], size: [9.3, 3.2, 12.4], rotationY: -0.44, kind: .communityGazebo),
        .init(id: "b_1467572222", position: [88.0, 0, 523.5], size: [7.4, 3.2, 11.1], rotationY: -0.12, kind: .communityGazebo),
        .init(id: "b_1467572223", position: [86.5, 0, 533.0], size: [7.0, 3.2, 11.4], rotationY: 0.07, kind: .residentialStiltHouse),
        .init(id: "b_1467572224", position: [54.1, 0, 544.3], size: [6.8, 3.2, 12.2], rotationY: -0.29, kind: .communityGazebo),
        .init(id: "b_1467572225", position: [54.5, 0, 531.5], size: [6.5, 3.2, 12.1], rotationY: 0.39, kind: .residentialStiltHouse),
        .init(id: "b_1467572226", position: [54.5, 0, 518.9], size: [6.9, 3.2, 11.7], rotationY: 0.02, kind: .communityGazebo),
        .init(id: "b_1467572227", position: [64.3, 0, 537.1], size: [7.6, 3.2, 12.8], rotationY: 0.04, kind: .communityGazebo),
        .init(id: "b_1467572228", position: [64.5, 0, 523.7], size: [9.9, 3.2, 13.3], rotationY: -0.34, kind: .communityGazebo),
        .init(id: "b_1467572229", position: [69.6, 0, 508.8], size: [11.8, 3.2, 14.9], rotationY: -0.51, kind: .communityGazebo),
        .init(id: "b_1467572230", position: [60.9, 0, 506.6], size: [11.8, 3.2, 13.8], rotationY: -0.0, kind: .communityGazebo),
        .init(id: "b_1467572231", position: [67.4, 0, 497.4], size: [13.0, 3.2, 13.9], rotationY: 0.08, kind: .communityGazebo),
        .init(id: "b_1467572232", position: [74.3, 0, 501.6], size: [12.1, 3.2, 12.7], rotationY: -0.47, kind: .communityGazebo),
        .init(id: "b_1467572233", position: [82.3, 0, 492.7], size: [9.9, 3.2, 9.7], rotationY: -0.3, kind: .communityGazebo),
        .init(id: "b_1467572234", position: [74.7, 0, 489.0], size: [9.6, 3.2, 9.5], rotationY: 0.23, kind: .communityGazebo),
        .init(id: "b_1467572235", position: [94.0, 0, 499.0], size: [8.5, 3.2, 8.7], rotationY: 0.52, kind: .residentialStiltHouse),
        .init(id: "b_1467572236", position: [86.9, 0, 507.0], size: [11.7, 3.2, 12.5], rotationY: 0.37, kind: .communityGazebo),
        .init(id: "b_1467572237", position: [75.6, 0, 526.6], size: [11.9, 3.2, 19.1], rotationY: 0.34, kind: .communityGazebo),
        .init(id: "b_1467572238", position: [116.7, 0, 116.3], size: [8.5, 3.2, 8.5], rotationY: -0.18, kind: .residentialStiltHouse),
        .init(id: "b_1467572239", position: [133.2, 0, 107.5], size: [12.6, 3.2, 10.6], rotationY: 0.45, kind: .communityGazebo),
        .init(id: "b_1467572240", position: [117.0, 0, 107.4], size: [13.3, 3.2, 9.7], rotationY: -0.43, kind: .communityGazebo),
        .init(id: "b_1467572241", position: [121.9, 0, 99.3], size: [14.0, 3.2, 12.0], rotationY: -0.41, kind: .communityGazebo),
        .init(id: "b_1467572242", position: [139.3, 0, 87.7], size: [11.8, 3.2, 9.1], rotationY: 0.19, kind: .communityGazebo),
        .init(id: "b_1467572243", position: [129.0, 0, 79.4], size: [12.4, 3.2, 9.8], rotationY: 0.44, kind: .communityGazebo),
        .init(id: "b_1467572244", position: [125.8, 0, 86.0], size: [12.8, 3.2, 9.9], rotationY: 0.46, kind: .communityGazebo),
        .init(id: "b_1467572245", position: [112.9, 0, 88.5], size: [11.1, 3.2, 9.8], rotationY: -0.17, kind: .communityGazebo),
        .init(id: "b_1467572246", position: [78.6, 0, 78.7], size: [13.3, 3.2, 12.2], rotationY: -0.22, kind: .communityGazebo),
        .init(id: "b_1467572247", position: [86.9, 0, 60.2], size: [9.5, 3.2, 8.9], rotationY: -0.32, kind: .communityGazebo),
        .init(id: "b_1467572248", position: [103.0, 0, 50.6], size: [13.3, 3.2, 10.9], rotationY: 0.26, kind: .communityGazebo),
        .init(id: "b_1467572249", position: [125.4, 0, 55.0], size: [12.5, 3.2, 10.6], rotationY: -0.49, kind: .communityGazebo),
        .init(id: "b_1467572250", position: [137.5, 0, 59.7], size: [14.2, 3.2, 12.4], rotationY: 0.31, kind: .communityGazebo),
        .init(id: "b_1467572251", position: [152.0, 0, 74.9], size: [12.2, 3.2, 7.3], rotationY: 0.5, kind: .communityGazebo),
        .init(id: "b_1467572252", position: [154.0, 0, 53.3], size: [9.3, 3.2, 8.1], rotationY: -0.03, kind: .residentialStiltHouse),
        .init(id: "b_1467572253", position: [157.7, 0, 45.3], size: [12.5, 3.2, 9.3], rotationY: -0.07, kind: .communityGazebo)
    ]
}

/// Generates low-poly 3D extruded wooden stilt houses and structures
enum SettlementMeshBuilder {
    static func makeBuildingEntity(_ b: SettlementBuilding) -> ModelEntity {
        let root = ModelEntity()
        root.name = b.id

        // Realistic materials matching the illustrated woodcut aesthetics
        let woodTone = UIColor(red: 0.42, green: 0.29, blue: 0.18, alpha: 1.0)
        let wallTone = UIColor(red: 0.76, green: 0.68, blue: 0.52, alpha: 1.0)
        let thatchRoof = UIColor(red: 0.32, green: 0.22, blue: 0.14, alpha: 1.0)

        let stiltHeight: Float = 0.6
        let bodyHeight: Float = b.size.y - 1.2
        let roofHeight: Float = 1.2

        // 1. Stilts (Panggung foundation)
        let stiltMesh = MeshResource.generateBox(size: [0.18, stiltHeight, 0.18])
        let stiltMat = SimpleMaterial(color: woodTone, roughness: 0.9, isMetallic: false)
        for dx: Float in [-b.size.x/2 + 0.3, b.size.x/2 - 0.3] {
            for dz: Float in [-b.size.z/2 + 0.3, b.size.z/2 - 0.3] {
                let leg = ModelEntity(mesh: stiltMesh, materials: [stiltMat])
                leg.position = [dx, stiltHeight / 2, dz]
                root.addChild(leg)
            }
        }

        // 2. Main Wall Body (Sasag woven bamboo)
        let bodyMesh = MeshResource.generateBox(size: [b.size.x - 0.2, bodyHeight, b.size.z - 0.2])
        let bodyMat = SimpleMaterial(color: wallTone, roughness: 0.85, isMetallic: false)
        let body = ModelEntity(mesh: bodyMesh, materials: [bodyMat])
        body.position = [0, stiltHeight + bodyHeight / 2, 0]
        root.addChild(body)

        // 3. Gable Roof (Suhunan Ijuk / Traditional Thatch Roof)
        let roofHalfW = (b.size.x + 0.5) / 2
        let roofMesh = MeshResource.generateBox(size: [roofHalfW, 0.12, b.size.z + 0.6])
        let roofMat = SimpleMaterial(color: thatchRoof, roughness: 0.95, isMetallic: false)

        for side: Float in [-1, 1] {
            let slope = ModelEntity(mesh: roofMesh, materials: [roofMat])
            slope.position = [side * (roofHalfW / 2 - 0.05), stiltHeight + bodyHeight + roofHeight / 2, 0]
            slope.orientation = simd_quatf(angle: -side * 0.55, axis: [0, 0, 1])
            root.addChild(slope)
        }

        // Apply orientation
        root.orientation = simd_quatf(angle: b.rotationY, axis: [0, 1, 0])
        return root
    }
}
