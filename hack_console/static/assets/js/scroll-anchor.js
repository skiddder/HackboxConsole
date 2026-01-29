/**
 * Scroll Anchor for MD View
 * Preserves scroll position when md-view width changes on hover
 * Works around Shadow DOM limitations with overflow-anchor
 * Also handles delayed expansion (10s hover to expand, instant collapse)
 */

export function initScrollAnchor() {
    const mdView = document.querySelector('.md-view');
    if (!mdView) return;

    let anchorElement = null;
    let anchorOffset = 0;
    let expandTimeout = null;
    const EXPAND_DELAY = 10000; // 10 seconds

    // Find the first visible element in the md-view
    function findFirstVisibleElement() {
        const viewportTop = window.scrollY;
        const viewportBottom = viewportTop + window.innerHeight;
        
        // Get all potential anchor elements (headings, paragraphs, etc.)
        const zeroMd = mdView.querySelector('zero-md');
        if (!zeroMd || !zeroMd.shadowRoot) {
            // Fallback to md-view itself
            return { element: mdView, offset: mdView.getBoundingClientRect().top };
        }

        // Look for elements in the shadow DOM
        const candidates = zeroMd.shadowRoot.querySelectorAll('h1, h2, h3, h4, h5, h6, p, li, pre, table, img');
        
        for (const el of candidates) {
            const rect = el.getBoundingClientRect();
            // Find first element that's at least partially visible
            if (rect.top >= 0 && rect.top < window.innerHeight * 0.5) {
                return { element: el, offset: rect.top };
            }
        }

        // Fallback to md-view
        return { element: mdView, offset: mdView.getBoundingClientRect().top };
    }

    // Save anchor before transition
    function saveAnchor() {
        const result = findFirstVisibleElement();
        anchorElement = result.element;
        anchorOffset = result.offset;
    }

    // Restore scroll position after transition
    function restoreAnchor() {
        if (!anchorElement) return;
        
        // Wait for transition to complete
        requestAnimationFrame(() => {
            const newRect = anchorElement.getBoundingClientRect();
            const scrollAdjustment = newRect.top - anchorOffset;
            
            if (Math.abs(scrollAdjustment) > 5) {
                window.scrollBy({
                    top: scrollAdjustment,
                    behavior: 'instant'
                });
            }
            
            // Clear flag after scroll adjustment (with small delay for safety)
            requestAnimationFrame(() => {
                window._scrollAnchorAdjusting = false;
            });
        });
    }

    // Helper to start/restart the expansion timer
    function startExpandTimer() {
        // Don't restart if already expanded
        if (mdView.classList.contains('expanded')) return;
        
        // Clear any pending timeout
        if (expandTimeout) {
            clearTimeout(expandTimeout);
        }
        
        // Start delayed expansion
        expandTimeout = setTimeout(() => {
            saveAnchor();
            // Set flag BEFORE transition starts to block scroll events during reflow
            window._scrollAnchorAdjusting = true;
            mdView.classList.add('expanded');
        }, EXPAND_DELAY);
    }

    let isMouseOver = false;

    // Listen for mouseenter/mouseleave on md-view
    mdView.addEventListener('mouseenter', () => {
        isMouseOver = true;
        startExpandTimer();
    });
    
    mdView.addEventListener('mouseleave', () => {
        isMouseOver = false;
        
        // Clear pending expansion timeout
        if (expandTimeout) {
            clearTimeout(expandTimeout);
            expandTimeout = null;
        }
        
        // Immediately collapse if expanded
        if (mdView.classList.contains('expanded')) {
            saveAnchor();
            // Set flag BEFORE transition starts to block scroll events during reflow
            window._scrollAnchorAdjusting = true;
            mdView.classList.remove('expanded');
        }
    });

    // Reset timer on mouse move within md-view (user is actively reading)
    mdView.addEventListener('mousemove', () => {
        if (isMouseOver) {
            startExpandTimer();
        }
    });

    // Reset timer on scroll while mouse is over md-view
    window.addEventListener('scroll', () => {
        if (isMouseOver && !window._scrollAnchorAdjusting) {
            startExpandTimer();
        }
    });

    // Click on handle to immediately toggle expanded state
    const handle = mdView.querySelector('.md-view-handle');
    if (handle) {
        handle.addEventListener('click', (e) => {
            e.stopPropagation();
            
            // Clear any pending timeout
            if (expandTimeout) {
                clearTimeout(expandTimeout);
                expandTimeout = null;
            }
            
            saveAnchor();
            window._scrollAnchorAdjusting = true;
            mdView.classList.toggle('expanded');
        });
    }

    // Listen for transition end to restore position
    mdView.addEventListener('transitionend', (e) => {
        if (e.propertyName === 'width' || e.propertyName === 'margin-left') {
            restoreAnchor();
        }
    });
}

// Auto-initialize if DOM is ready
function init() {
    const mdView = document.querySelector('.md-view');
    if (!mdView) {
        console.log('[scroll-anchor] No .md-view found, skipping initialization');
        return;
    }
    console.log('[scroll-anchor] Initializing scroll anchor for md-view');
    initScrollAnchor();
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
