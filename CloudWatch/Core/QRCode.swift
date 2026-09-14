import Foundation
/// QR Model 2, version 5-L, byte mode, mask 0. Capacity: 106 UTF-8 bytes.
/// Fixed size is sufficient for the official short authorization URL.
public enum LoginQRCode {
    public static func matrix(_ text: String) -> [[Bool]]? {
        let bytes = Array(text.utf8); guard bytes.count <= 106 else { return nil }
        var bits: [Bool] = []
        func append(_ value: Int, _ count: Int) { for i in (0..<count).reversed() { bits.append((value >> i) & 1 != 0) } }
        append(4,4); append(bytes.count,8); bytes.forEach { append(Int($0),8) }
        append(0,min(4,864-bits.count)); while bits.count % 8 != 0 { bits.append(false) }
        var data = stride(from:0,to:bits.count,by:8).map { start in (0..<8).reduce(UInt8(0)) { ($0 << 1) | (bits[start+$1] ? 1 : 0) } }
        while data.count < 108 { data.append((data.count - (bits.count/8)) % 2 == 0 ? 0xEC : 0x11) }
        func multiply(_ x: UInt8, _ y: UInt8) -> UInt8 {
            var z = 0
            for i in (0..<8).reversed() { z = (z << 1) ^ ((z >> 7) * 0x11D); z ^= Int(x) * Int((y >> i) & 1) }
            return UInt8(z)
        }
        var divisor = [UInt8](repeating:0,count:26); divisor[25] = 1; var root: UInt8 = 1
        for _ in 0..<26 { for j in 0..<26 { divisor[j] = multiply(divisor[j],root); if j+1 < 26 { divisor[j] ^= divisor[j+1] } }; root = multiply(root,2) }
        var remainder = [UInt8](repeating:0,count:26)
        for b in data { let factor = b ^ remainder[0]; remainder.removeFirst(); remainder.append(0); for i in 0..<26 { remainder[i] ^= multiply(divisor[i],factor) } }
        let codewords = data + remainder; let n = 37
        var m = Array(repeating:Array(repeating:false,count:n),count:n), function = m
        func set(_ x: Int,_ y: Int,_ value: Bool) { guard x>=0,y>=0,x<n,y<n else { return }; m[y][x]=value; function[y][x]=true }
        for i in 0..<n { set(6,i,i%2 == 0); set(i,6,i%2 == 0) }
        for (cx,cy) in [(3,3),(n-4,3),(3,n-4)] {
            for dy in -4...4 { for dx in -4...4 { let d = max(abs(dx),abs(dy)); set(cx+dx,cy+dy,d != 2 && d != 4) } }
        }
        for dy in -2...2 { for dx in -2...2 { set(30+dx,30+dy,max(abs(dx),abs(dy)) != 1) } }
        // Error correction L = 01, mask = 000.
        let formatData = 8; var rem = formatData
        for _ in 0..<10 { rem = (rem << 1) ^ ((rem >> 9) * 0x537) }
        let format = ((formatData << 10) | rem) ^ 0x5412
        func bit(_ i: Int) -> Bool { (format >> i) & 1 != 0 }
        for i in 0..<6 { set(8,i,bit(i)) }; set(8,7,bit(6)); set(8,8,bit(7)); set(7,8,bit(8))
        for i in 9..<15 { set(14-i,8,bit(i)) }
        for i in 0..<8 { set(n-1-i,8,bit(i)) }
        for i in 8..<15 { set(8,n-15+i,bit(i)) }; set(8,n-8,true)
        var index = 0, right = n-1
        while right >= 1 {
            if right == 6 { right = 5 }
            for vertical in 0..<n {
                let y = ((right+1)&2) == 0 ? n-1-vertical : vertical
                for j in 0..<2 { let x = right-j; if !function[y][x] {
                    let value = index < codewords.count*8 ? ((codewords[index>>3] >> (7-(index&7))) & 1) != 0 : false
                    m[y][x] = value != ((x+y)%2 == 0); index += 1
                } }
            }; right -= 2
        }
        return m
    }
}
