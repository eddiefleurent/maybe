<!-- Simplified approach since Yodlee's initialize.js script returns Internal Server Error -->
<script>
  window.addEventListener('load', function() {
    console.log('Page loaded');
    console.log('FastLink URL:', '<%= @token_response.fastlink_url %>');
    console.log('Token:', '<%= @token_response.user_token ? @token_response.user_token[0..10] + "..." : "NO TOKEN" %>');
    
    // iFrame approach
    const iframeButton = document.getElementById('launch-yodlee-iframe');
    if (iframeButton) {
      iframeButton.onclick = function() {
        console.log('iFrame button clicked!');
        
        const container = document.getElementById('fastlink-container');
        const iframe = document.getElementById('fastlink-iframe');
        
        if (container && iframe) {
          // Show the container
          container.classList.remove('hidden');
          
          // Build FastLink URL with parameters
          const fastlinkUrl = '<%= @token_response.fastlink_url %>';
          const bearerToken = 'Bearer <%= @token_response.user_token %>';
          
          const iframeUrl = fastlinkUrl + 
            '?accessToken=' + encodeURIComponent(bearerToken) +
            '&configName=Aggregation';
          
          console.log('Loading FastLink in iFrame:', iframeUrl);
          iframe.src = iframeUrl;
          
          // Disable button
          iframeButton.disabled = true;
          iframeButton.textContent = 'FastLink Loading...';
        }
      };
    }
    
    // Direct link approach  
    const testButton = document.getElementById('test-direct-yodlee');
    if (testButton) {
      testButton.onclick = function() {
        const fastlinkUrl = '<%= @token_response.fastlink_url %>';
        const bearerToken = 'Bearer <%= @token_response.user_token %>';
        
        // Construct direct URL with corrected parameters
        const directUrl = fastlinkUrl + 
          '?accessToken=' + encodeURIComponent(bearerToken) +
          '&configName=Aggregation';
          
        console.log('Opening direct URL:', directUrl);
        window.open(directUrl, '_blank', 'width=800,height=600');
      };
    }
  });
</script>