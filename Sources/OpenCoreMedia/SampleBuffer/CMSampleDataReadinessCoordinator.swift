actor CMSampleDataReadinessCoordinator {
    private let handler: CMSampleBufferMakeDataReadyHandler?
    private var isLoading = false

    init(handler: CMSampleBufferMakeDataReadyHandler?) {
        self.handler = handler
    }

    func resolved(
        from current: CMSampleBufferDataReadiness
    ) async throws(CMSampleBufferError) -> CMSampleBufferDataReadiness {
        switch current {
        case .ready:
            return .ready
        case .failed(let code):
            throw .dataFailed(code: code)
        case .notReady:
            break
        }

        guard !isLoading else {
            throw .dataLoadingInProgress
        }
        guard let handler else {
            throw .dataNotReady
        }

        isLoading = true
        let result = await handler()
        isLoading = false
        return result
    }
}
