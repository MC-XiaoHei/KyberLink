pub trait MdioPins {
    fn mdc(&self, level: bool);
    fn mdio(&self, level: bool);
    fn mdio_level(&self) -> bool;
}

impl<T: MdioPins> MdioPins for &T {
    fn mdc(&self, level: bool) {
        (**self).mdc(level);
    }

    fn mdio(&self, level: bool) {
        (**self).mdio(level);
    }

    fn mdio_level(&self) -> bool {
        (**self).mdio_level()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MdioError {
    NoResponse,
    BadAddress,
}

#[cfg(test)]
pub(crate) mod mock {
    use super::MdioPins;
    use core::cell::RefCell;

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub enum Edge {
        Mdc(bool),
        Mdio(bool),
    }

    pub struct Recorder {
        pub edges: RefCell<Vec<Edge>>,
    }

    impl Recorder {
        pub fn new() -> Self {
            Self {
                edges: RefCell::new(Vec::new()),
            }
        }

        pub fn sampled_bits(&self) -> Vec<bool> {
            let mut bits = Vec::new();
            let mut driven = true;
            for e in self.edges.borrow().iter() {
                match e {
                    Edge::Mdio(v) => driven = *v,
                    Edge::Mdc(true) => bits.push(driven),
                    Edge::Mdc(false) => {}
                }
            }
            bits
        }
    }

    impl MdioPins for Recorder {
        fn mdc(&self, level: bool) {
            self.edges.borrow_mut().push(Edge::Mdc(level));
        }

        fn mdio(&self, level: bool) {
            self.edges.borrow_mut().push(Edge::Mdio(level));
        }

        fn mdio_level(&self) -> bool {
            true
        }
    }
}
