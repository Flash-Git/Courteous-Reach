import React, { Component } from 'react';

class Navbar extends Component {
  state = {
    isOpen: false
  }

  toggle = () => {
    this.setState({
      isOpen: !this.state.isOpen
    });
  }

  render(){
    return(
      <div>
      </div>
    );
  }
}

export default Navbar; 