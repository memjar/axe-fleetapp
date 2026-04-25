import SwiftUI

struct EventToastBanner: View {
    let event: FleetEvent
    
    var body: some View {
        HStack(spacing: 12) {
            // Severity icon
            Image(systemName: event.icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(severityColor)
                .cornerRadius(8)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Text(event.source)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text(event.severity.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(severityColor)
                    
                    Spacer()
                    
                    Text(event.timestamp, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(severityColor.opacity(0.6), lineWidth: 1)
                )
        )
        .shadow(color: severityColor.opacity(0.3), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
    
    private var severityColor: Color {
        switch event.severity.lowercased() {
        case "critical": return .red
        case "warning": return .orange
        case "info": return .blue
        default: return .gray
        }
    }
}
